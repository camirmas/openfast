!**********************************************************************************************************************************
! LICENSING
! Copyright (C) 2015-2016  National Renewable Energy Laboratory
!
!    This file is part of AeroDyn.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!
!**********************************************************************************************************************************
program AeroDyn_Model

   use AeroDyn_Model_Subs   
    
   implicit none   
   
   ! Program variables

   real(DbKi)                                     :: time                 !< Variable for storing time, in seconds 
   real(DbKi)                                     :: dT_Dvr               !< copy of DT, to make sure AD didn't change it
                                                    
   type(Dvr_SimData)                              :: DvrData              ! The data required for running the AD driver
   type(AD_InputType)                             :: PhysData             ! Physical model data
   type(AeroDyn_Data)                             :: AD                   ! AeroDyn data 
                                                  
   integer(IntKi)                                 :: iCase                ! loop counter (for driver case)
   integer(IntKi)                                 :: nt                   ! loop counter (for time step)
   integer(IntKi)                                 :: j                    ! loop counter (for array of inputs)
   integer(IntKi)                                 :: numSteps             ! number of time steps in the simulation
   integer(IntKi)                                 :: errStat              ! Status of error message
   character(ErrMsgLen)                           :: errMsg               ! Error message if ErrStat /= ErrID_None
   
   character(1024)                                :: Phys_HubFile         ! Name of file containing current physical hub data
   character(1024)                                :: Phys_TwrFile         ! Name of file containing current physical tower data
   character(1024)                                :: Phys_OutFile         ! Name of file containing data to be sent to the physical model
   integer                                        :: OutUn                ! Unit for the output hybrid file.
   integer                                        :: HubUn                ! Unit for the input hub file
   integer                                        :: TwrUn                ! Unit for the input tower file

   !integer                                        :: StrtTime (8)                            ! Start time of simulation (including intialization)
   !integer                                        :: SimStrtTime (8)                         ! Start time of simulation (after initialization)
   !real(ReKi)                                     :: PrevClockTime                           ! Clock time at start of simulation in seconds
   !real                                           :: UsrTime1                                ! User CPU time for simulation initialization
   !real                                           :: UsrTime2                                ! User CPU time for simulation (without intialization)
   !real                                           :: UsrTimeDiff                             ! Difference in CPU time from start to finish of program execution
   !real(DbKi)                                     :: TiLstPrn                                ! The simulation time of the last print
   !real(DbKi)                                     :: SttsTime                                ! Amount of time between screen status messages (sec)
   !integer                                        :: n_SttsTime                              ! Number of time steps between screen status messages (-)
   logical                                        :: AD_Initialized
                            

   errStat     = ErrID_None
   errMsg      = ''
   AD_Initialized = .false.
   Phys_OutFile = 'C:\Users\devin\OneDrive\Documents\College\Research\Code\Fake Wind\OpenFAST source code\num_mod_outputs.out' ! @mcd: make this more general later
   
   time        = 0.0 ! seconds
      
            
      ! Get the current time
   !call date_and_time ( Values=StrtTime )                               ! Let's time the whole simulation
   !call cpu_time ( UsrTime1 )                                           ! Initial time (this zeros the start time when used as a MATLAB function)
   
   
      ! initialize this driver:
   call Dvr_Init( DvrData, ErrStat, ErrMsg)
      call CheckError()
   
   do iCase = 1, DvrData%NumCases
      call WrScr( NewLine//'Running case '//trim(num2lstr(iCase))//' of '//trim(num2lstr(DvrData%NumCases))//'.' )
   
      
      !dT = TwoPi/DvrData%Cases(iCase)%RotSpeed / DvrData%NumSect ! sec
      ! @mcd: keep this for now, but it is likely that we will replace the driver file at some point
      numSteps = ceiling( DvrData%Cases(iCase)%TMax / DvrData%Cases(iCase)%dT)      
      dT_Dvr   = DvrData%Cases(iCase)%dT
      
      call WrScr ('   WndSpeed='//trim(num2lstr(DvrData%Cases(iCase)%WndSpeed))//&
               ' m/s; ShearExp='//trim(num2lstr(DvrData%Cases(iCase)%ShearExp))//&
                   '; RotSpeed='//trim(num2lstr(DvrData%Cases(iCase)%RotSpeed*RPS2RPM))//&
                  ' rpm; Pitch='//trim(num2lstr(DvrData%Cases(iCase)%Pitch*R2D))//&
                    ' deg; Yaw='//trim(num2lstr(DvrData%Cases(iCase)%Yaw*R2D))//&
                     ' deg; dT='//trim(num2lstr(DvrData%Cases(iCase)%dT))//&
                     ' s; Tmax='//trim(num2lstr(DvrData%Cases(iCase)%Tmax))//&
                 ' s; numSteps='//trim(num2lstr(numSteps)) )
      
      
         ! Set the Initialization input data for AeroDyn based on the Driver input file data, and initialize AD
         ! (this also initializes inputs to AD for first time step)
      call Init_AeroDyn(iCase, DvrData, AD, PhysData, dT_Dvr, Phys_HubFile, Phys_TwrFile, errStat, errMsg)
         call CheckError()
         AD_Initialized = .true.
         
         if (.not. EqualRealNos( dT_Dvr, DvrData%Cases(iCase)%dT ) ) then
            ErrStat = ErrID_Fatal
            ErrMsg = 'AeroDyn changed the time step for case '//trim(num2lstr(iCase))//'. Change DTAero to "default".'
            call CheckError()
         end if
      
      call Dvr_InitializeOutputFile( iCase, DvrData%Cases(iCase), DvrData%OutFileData, errStat, errMsg)
         call CheckError()
      
      
      do nt = 1, numSteps
          
          ! Open hybrid interface files
        call GetNewUnit(HubUn) ! hub input file
            open (HubUn, file=Phys_HubFile, status='OLD', action='READWRITE', iostat=errStat)
                if (errStat .ne. 0) then
                    do while (errStat .ne. 0)
                        call sleepqq(1)
                        open(HubUn, file=Phys_HubFile, status='OLD', action='READWRITE', iostat=errStat)
                    end do
                end if
        call GetNewUnit(TwrUn) ! tower input file
            open (TwrUn, file=Phys_TwrFile, status='OLD', action='READWRITE', iostat=errStat)
                if (errStat .ne. 0) then
                    do while (errStat .ne. 0)
                        call sleepqq(1)
                        open(TwrUn, file=Phys_TwrFile, status='OLD', action='READWRITE', iostat=errStat)
                    end do
                end if
        call GetNewUnit(OutUn) ! force output file
            open (OutUn, file=Phys_OutFile, status='NEW', action='WRITE', iostat=errStat)
                if (errStat .ne. 0) then
                    do while (errStat .ne. 0)
                        call sleepqq(1)
                        open(OutUn, file=Phys_OutFile, status='NEW', action='WRITE', iostat=errStat)
                    end do
                end if
         
         ! Get current motion information from physical model (physical model input files are deleted at the end of this routine)
          call PhysMod_Get_Physical_Motions(PhysData, HubUn, TwrUn)
          
         !...............................
         ! set AD inputs for nt from physical model (and keep values at nt-1 as well)
         !...............................
          call Set_AD_Motion_Inputs_NoIfW(iCase,nt,DvrData,AD,PhysData,errStat,errMsg)
          call Set_AD_Inflows(iCase,nt,DvrData,AD,errStat,errMsg)  
            call CheckError()
   
         time = AD%InputTime(2)

            ! Calculate outputs at nt - 1

         call AD_CalcOutput( time, AD%u(2), AD%p, AD%x, AD%xd, AD%z, AD%OtherState, AD%y, AD%m, errStat, errMsg )
            call CheckError()

            ! @mcd: this is modified to write output to both normal output file and hybrid interface file
         call Dvr_WriteOutputLine(DvrData%OutFileData, time, AD%y%WriteOutput, OutUn, errStat, errMsg)
            call CheckError()
            
            ! Get state variables at next step: INPUT at step nt - 1, OUTPUT at step nt
         call AD_UpdateStates( time, nt-1, AD%u, AD%InputTime, AD%p, AD%x, AD%xd, AD%z, AD%OtherState, AD%m, errStat, errMsg )
            call CheckError()
                  
            ! Close and delete current hybrid output file
            close(OutUn, status='DELETE')
            
      end do !nt=1,numSteps
      
      call AD_End( AD%u(1), AD%p, AD%x, AD%xd, AD%z, AD%OtherState, AD%y, AD%m, errStat, errMsg )
         AD_Initialized = .false.         
         call CheckError()
         close( DvrData%OutFileData%unOutFile )
               
      do j = 2, numInp
         call AD_DestroyInput (AD%u(j),  errStat, errMsg)
            call CheckError()
      end do
         
   end do !iCase = 1, DvrData%NumCases
   
   
   call Dvr_End()
   
contains
!................................   
   subroutine CheckError()
   
      if (ErrStat /= ErrID_None) then
         call WrScr(TRIM(ErrMsg))
         
         if (ErrStat >= AbortErrLev) then
            call Dvr_End()
         end if
      end if
         
   end subroutine CheckError
!................................   
   subroutine Dvr_End()
   
         ! Local variables
      character(ErrMsgLen)                          :: errMsg2                 ! temporary Error message if ErrStat /= ErrID_None
      integer(IntKi)                                :: errStat2                ! temporary Error status of the operation
      
      character(*), parameter                       :: RoutineName = 'Dvr_End'
         ! Close the output file
      if (DvrData%OutFileData%unOutFile > 0) close(DvrData%OutFileData%unOutFile)
            
      if ( AD_Initialized ) then
         call AD_End( AD%u(1), AD%p, AD%x, AD%xd, AD%z, AD%OtherState, AD%y, AD%m, errStat2, errMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
      end if
           
      call AD_Dvr_DestroyDvr_SimData( DvrData, ErrStat2, ErrMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )

      call AD_Dvr_DestroyAeroDyn_Data( AD, ErrStat2, ErrMsg2 )
         call SetErrStat( errStat2, errMsg2, errStat, errMsg, RoutineName )
               
      if (ErrStat >= AbortErrLev) then      
         CALL ProgAbort( 'AeroDyn Driver encountered simulation error level: '&
             //TRIM(GetErrStr(ErrStat)), TrapErrors=.FALSE., TimeWait=3._ReKi )  ! wait 3 seconds (in case they double-clicked and got an error)
      else
         call NormStop()
      end if
      
      
   end subroutine Dvr_End
!................................   
end program AeroDyn_Model
   