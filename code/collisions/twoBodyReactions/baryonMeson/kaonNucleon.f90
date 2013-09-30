!****************************************************************************
!****m* /kaonNucleon
! NAME
! module kaonNucleon
!
! PURPOSE
! Includes the cross sections for kaon-nucleon and antikaon-antinucleon 
! elastic and inelastic scattering
!
! Public routines:
! * kaonNuc 
!****************************************************************************
module kaonNucleon

  implicit none
  Private

  ! Debug-flags
  logical,parameter :: debugFlag=.false.
  logical,parameter :: debugFlagAnti=.false.

  ! To decide wether we use the flux correction for the incoming particle velocities
  logical, parameter :: fluxCorrector_flag=.true.

  Public :: kaonNuc

contains

  !****************************************************************************
  !****s* kaonNucleon/kaonNuc
  ! NAME
  ! subroutine kaonNuc (srts,teilchenIN,teilchenOUT,sigmaTot,sigmaElast,plotFlag)
  !
  ! PURPOSE
  ! Evaluates the cross sections for 
  ! * K N -> K N, 
  ! * Kbar Nbar -> Kbar Nbar, 
  ! * K N -> K N pi, 
  ! * Kbar Nbar -> Kbar Nbar pi
  ! and returns also a "preevent"
  !
  ! Possible final states are :
  ! * 2-particle : K N
  ! * 3-particle : K N pi  
  !
  ! This routine does a Monte-Carlo-decision according to the partial cross sections to decide on a final state with
  ! maximal 3 final state particles. These are returned in the vector teilchenOut. The kinematics of these teilchen is
  ! only fixed in the case of a single produced resonance. Otherwise the kinematics still need to be established. The
  ! result is:
  ! * type(preEvent),dimension(1:3), intent(out)               :: teilchenOut    !   outgoing particles
  ! 
  ! The cross sections are based on parameterization by M. Effenberger. 
  !
  ! INPUTS
  ! * real, intent(in)                              :: srts                  ! sqrt(s) in the process
  ! * type(particle),dimension(1:2), intent(in)     :: teilchenIn            ! colliding particles
  !
  ! Debugging:
  ! * logical, intent(in),optional                  :: plotFlag              ! Switch on plotting of the  Xsections 
  ! 
  ! OUTPUT
  ! * real, intent(out)                             :: sigmaTot              ! total Xsection
  ! * real, intent(out)                             :: sigmaElast            ! elastic Xsection
  ! 
  !***************************************************************************
  subroutine kaonNuc (srts,teilchenIN,teilchenOUT,sigmaTot,sigmaElast,plotFlag)
  use idTable, only : nucleon, pion, kaon, kaonBar
  use particleDefinition
  use mediumDefinition
  use preEventDefinition, only : preEvent
  use twoBodyTools, only : velocity_correction,p_lab,searchInInput,ranCharge,&
                         & convertToAntiParticles
  use RMF, only : getRMF_flag

  ! INPUT:
  real, intent(in)                              :: srts                  ! sqrt(s) in the process
  type(particle),dimension(1:2), intent(in)     :: teilchenIn            ! colliding particles
  logical, intent(in),optional                  :: plotFlag    ! Switch on plotting of the  Xsections

  ! OUTPUT:
  real, intent(out)                             :: sigmaTot   ! total Xsection
  real, intent(out)                             :: sigmaElast ! elastic Xsection
  type(preEvent),dimension(1:3), intent(out)    :: teilchenOut !   outgoing particles

  ! Cross sections:
  real :: sigma_KN        ! K N final state (elastic cross section + CEX cross section)
  real :: sigma_CEX       ! charge exchange cross section
  real :: sigma_KNpi      ! K N pi final state (inelastic cross section)

  ! Local variables
  real :: fluxCorrector        ! Correction of the fluxfactor due to different velocities 
                               ! in the medium compared to the vacuum
  type(particle) :: kaon_particle, nucleon_particle    
  logical :: antiParticleInput, failFlag
  integer :: totalCharge   ! total charge of colliding particles

  ! Initialize output
  teilchenOut(:)%ID=0                    ! ID of produced particles
  teilchenOut(:)%charge=0                ! Charge of produced particles
  teilchenOut(:)%antiParticle=.false.    ! Whether produced particles are particles or antiparticles
  teilchenOut(:)%mass=0.                 ! Mass of produced particles

  ! (1) Check  Input
  call searchInInput(teilchenIn,kaon,nucleon,kaon_particle,nucleon_particle,failFlag)
  If(failFlag) then
    call searchInInput(teilchenIn,kaonBar,nucleon,kaon_particle,nucleon_particle,failFlag)
    if(failFlag) then
      Write(*,*) 'Wrong input in kaonNuc', teilchenIn%ID
      stop
    end if
  end if

  If(kaon_particle%antiParticle) then   ! This must not happen!
    write(*,*) 'kaon is antiparticle in "kaonNuc"!!!',teilchenIN%ID,teilchenIN%antiparticle
    stop
  end if

  If(kaon_particle%Id==kaonBar .and. nucleon_particle%antiParticle) then
    ! Invert all particles in antiparticles:
    nucleon_particle%Charge=-nucleon_particle%Charge
    nucleon_particle%antiparticle=.false.
    kaon_particle%Charge=-kaon_particle%Charge
    kaon_particle%Id=kaon
    antiParticleInput=.true.
  else if(kaon_particle%Id==kaonBar .or. nucleon_particle%antiParticle) then
    write(*,*) 'In kaonNuc: Kbar N and K Nbar collisions must be treated by another routine !', teilchenIn%ID
    stop
  else
    antiParticleInput=.false.
  end if

  ! Correction of the fluxfactor due to different velocities in the medium compared to the vacuum
  if( .not.getRMF_flag() ) then
    fluxCorrector=velocity_correction(teilchenIn)
  else
    fluxCorrector=1.
  end if

  ! (2) Evaluate the cross sections
  call evaluateXsections

  ! Cutoff to kick the case out, that the cross section is zero
  if(sigmaTot.lt.1E-12) then
    sigmatot=0.
    sigmaElast=0.
    return
  end if

  ! (3) Plot them if wished
  If(Present(PlotFlag).or.debugFlag) then
    If (plotFlag.or.debugFlag)  call makeOutput
  end if

  ! (4) Define final state
  call MakeDecision

  ! (5) Check Output
  If(Sum(teilchenOut(:)%Charge)&
    &.ne.nucleon_particle%charge+kaon_particle%charge) then
       write(*,*) 'No charge conservation in kaonNuc!!! Critical error',&
       &kaon_particle%Charge,nucleon_particle%Charge,&
       &teilchenOut(:)%Charge,teilchenOut(:)%ID
       stop
  end if

  ! (6) Invert particles in antiParticles if input included antiparticles
  If(antiParticleInput) then
     IF(debugFlagAnti) write(*,*) teilchenOut
     call convertToAntiParticles(teilchenOut)
     IF(debugFlagAnti) write(*,*) teilchenOut
  end if

contains

  !**************************************************************
  !****s* kaonNuc/evaluateXsections
  ! NAME
  ! subroutine evaluateXsections
  !
  ! PURPOSE
  ! Evaluates K N -> K N and K N -> K N pi cross sections 
  !
  ! NOTES
  ! There are no resonance contributions to K N scattering.
  !**************************************************************
  
  subroutine evaluateXsections

    use parametrizationsBarMes, only : sigelkp, kppbg, kpnbg, sigCEXkp, sigCEXk0
    use constants, only: mN, mPi, mK

    real :: plab

    plab=p_lab(srts,kaon_particle%mass,nucleon_particle%mass)

    totalCharge=kaon_particle%charge+nucleon_particle%charge

    if(kaon_particle%charge.eq.1 .and. nucleon_particle%charge.eq.0) then
       sigmaElast=sigelkp(plab,2)
       sigma_CEX=sigCEXkp(srts)
    else if(kaon_particle%charge.eq.0 .and. nucleon_particle%charge.eq.1) then
       sigmaElast=sigelkp(plab,2)
       sigma_CEX=sigCEXk0(srts)
    else
       sigmaElast=sigelkp(plab,1)
       sigma_CEX=0.
    end if

    if(srts > mN+mK+mPi) then
      if(totalCharge==1) then
        sigma_KNpi=kpnbg(plab)
      else
        sigma_KNpi=kppbg(plab)
      end if
    else
      sigma_KNpi=0.
    end if
      
    ! Flux correction for each channel:
    If(fluxCorrector_flag) then
      sigmaElast=sigmaElast*fluxcorrector
      sigma_CEX=sigma_CEX*fluxcorrector
      sigma_KNpi=sigma_KNpi*fluxcorrector
    end if

    sigma_KN=sigmaElast+sigma_CEX

    ! Total cross section:
    sigmaTot=sigma_KN+sigma_KNpi

  end subroutine evaluateXsections


    !**************************************************************
    !****s* kaonNuc/makeDecision
    ! NAME
    ! subroutine makeDecision
    !
    ! PURPOSE
    ! Chooses randomly one of possible outgoing channels in kaon-nucleon
    ! collision. Outgoing channels are: K N and K N pi. Also the charges
    ! of outgoing particles are selected. 
    !
    ! NOTES
    !**************************************************************
    subroutine makeDecision
      use random, only : rn

      real :: cut,x
!       integer,dimension (1:3)  :: izmin,izmax,izout     ! needed for ranCharge
!       logical :: ranChargeFlag

      cut=rn()*sigmaTot ! random number for Monte-Carlo decision

      If(sigma_KN >= cut) then

         ! Elastic scattering or CEX:       

         teilchenOut(1)%Id=kaon
         teilchenOut(2)%Id=nucleon

         if(totalCharge==1) then
           ! K^+ n or K^0 p incoming channel; choose CEX or elastic scattering
           if(sigma_CEX >= cut) then
              teilchenOut(1)%Charge=1-kaon_particle%charge
              teilchenOut(2)%Charge=1-nucleon_particle%charge
           else
              teilchenOut(1)%Charge=kaon_particle%charge
              teilchenOut(2)%Charge=nucleon_particle%charge
           end if
         else          
           ! K^+ p or K^0 n incoming channel; the charges of outgoing
           ! particles are fixed:
           teilchenOut(1)%Charge=kaon_particle%charge
           teilchenOut(2)%Charge=nucleon_particle%charge
         end if

      else if(sigma_KN+sigma_KNpi >= cut) then

         ! pi K N  final state:

         teilchenOut(1)%Id=pion
         teilchenOut(2)%Id=kaon
         teilchenOut(3)%Id=nucleon


!*****   Empirical branching ratios:
         x=rn()
         if(totalCharge.eq.2) then   ! K+ p     

            if(x.le.0.667) then          ! pi+ K0 p (2/3)
               teilchenOut(1)%Charge=1
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=1
            else if(x.le.0.889) then     ! pi0 K+ p (2/9)
               teilchenOut(1)%Charge=0
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=1
            else                         ! pi+ K+ n (1/9)
               teilchenOut(1)%Charge=1
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=0
            end if

         else if(totalCharge.eq.0) then  ! K0 n     

            ! obtained from K+p by isospin reflection:
            if(x.le.0.667) then          ! pi- K+ n (2/3)
               teilchenOut(1)%Charge=-1
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=0
            else if(x.le.0.889) then     ! pi0 K0 n (2/9)
               teilchenOut(1)%Charge=0
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=0
            else                         ! pi- K0 p (1/9)
               teilchenOut(1)%Charge=-1
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=1
            end if

         else if(kaon_particle%charge.eq.1 .and. nucleon_particle%charge.eq.0) then  !K+ n

!            izmin=(/-1,0,0/)
!            izmax=(/1,1,1/)
!            call rancharge(izmin,izmax,totalCharge,izout,ranChargeFlag)
!            If (.not.ranChargeFlag) write(*,*) 'Error in rancharge :',izmin,izmax,totalCharge,izout,ranChargeFlag
!            teilchenOut(1)%Charge=izout(1)
!            teilchenOut(2)%Charge=izout(2)
!            teilchenOut(3)%Charge=izout(3)

            if(x.le.0.39) then           ! pi- K+ p  (0.39)
               teilchenOut(1)%Charge=-1
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=1
            else if(x.le.0.65) then      ! pi0 K0 p (0.26)
               teilchenOut(1)%Charge=0
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=1
            else if(x.le.0.84) then      ! pi0 K+ n (0.19)
               teilchenOut(1)%Charge=0
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=0
            else                         ! pi+ K0 n (0.16)
               teilchenOut(1)%Charge=1
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=0
            end if


         else   ! K0 p

            ! obtained from K+ n by isospin reflection:
            if(x.le.0.39) then           ! pi+ K0 n  (0.39)
               teilchenOut(1)%Charge=1
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=0
            else if(x.le.0.65) then      ! pi0 K+ n (0.26)
               teilchenOut(1)%Charge=0
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=0
            else if(x.le.0.84) then      ! pi0 K0 p (0.19)
               teilchenOut(1)%Charge=0
               teilchenOut(2)%Charge=0
               teilchenOut(3)%Charge=1
            else                         ! pi- K+ p (0.16)
               teilchenOut(1)%Charge=-1
               teilchenOut(2)%Charge=1
               teilchenOut(3)%Charge=1
            end if

         end if

      else

         ! No event was generated:
         write(*,*) 'Error in makedecision of kaonNuc', &
                   & sigma_KN,sigma_KNpi,sigmaTot,cut
         stop

      end if

    end subroutine makeDecision

    !********************************************************************** 
    !****s* kaonNuc/makeOutput
    ! NAME
    ! subroutine makeOutput
    ! 
    ! PURPOSE
    ! Writes all cross sections to file as function of srts and plab [GeV]
    ! . 
    ! Filenames:
    ! * 'KN_sigTotElast.dat'        : sigmaTot, sigmaElast 
    ! * 'KN_KN_KNpi.dat'        : K N and and K N pi outgoing channels
    !********************************************************************** 
    subroutine makeOutPut

      logical, save :: initFlag=.true.

      ! The output files
      character(30), dimension(1:2) :: outputFile
      real :: plab


      outputFile(1)='KN_sigTotElast.dat'
      outputFile(2)='KN_KN_KNpi.dat'

      plab=p_lab(srts,kaon_particle%mass,nucleon_particle%mass)

      If (initFlag) then
         Open(file=outputFile(1),UNIT=101,Status='Replace',Action='Write')
         Open(file=outputFile(2),UNIT=102,Status='Replace',Action='Write')
         write (101,*) '#   srts,    plab,   sigmaTot,  sigmaElast'
         write (102,*) '#   srts,    plab,   KN,    CEX,     KNpi'
         initFlag=.false.
      else
         Open(file=outputFile(1),UNIT=101,Status='old',Position='Append',Action='Write')
         Open(file=outputFile(2),UNIT=102,Status='old',Position='Append',Action='Write')
      end If
      write (101,'(4F9.3)') srts, plab, sigmaTot, sigmaElast
      write (102,'(5F9.3)') srts, plab, sigma_KN, sigma_CEX, sigma_KNpi
      Close(101)
      Close(102)
    end subroutine makeOutPut

  end subroutine kaonNuc

end module kaonNucleon
