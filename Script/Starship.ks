//Script Creator: Kerbal Gamer
//Starship Launch Script 
//Version 2.1

runOncePath("0:/My_lib.ks").
runOncePath("0:/lib_lazcalc.ks").

//Mission Parameter's
set targetAP to 150000.//In meter's
set Inclination to 0.
set meco_deltaV to 1400.//ASDS[700],RTLS[1200]
set PitchSpeed to 0.311011.

set steeringManager:rollts to 50.
set steeringManager:maxstoppingtime to 0.45.
launch.
Ascent.
MECO.
stage2.
cricularize.

function launch{
  clearScreen.
  wait 5.
  lock steering to up.
  lock throttle to 1.
  stage.
  Print "Lift off ".
  wait until alt:radar > 100.
}

function Ascent{
 global az_data is LAZcalc_init(targetAp, Inclination).
  lock targetPitch to 90 - 1.03287 * alt:radar^PitchSpeed.

  until SHIP:STAGEDELTAV(SHIP:STAGENUM):CURRENT < Meco_DeltaV {
  Telemetry().
  local az_Hed is LAZcalc(az_data).
  lock steering to heading(az_Hed, targetPitch).
  }
}

function MECO{
  lock throttle to 0.
  toggle ag8.
  wait 1.
  stage.
  clearScreen.
  wait 3.5.
  lock throttle to 0.2.
  wait 2.
}

function stage2{
  clearScreen.
  Print "SES-1".
  rcs on.
  lock throttle to 1.
  until ship:apoapsis > targetAP - 100{
    Telemetry().
    lock targetPitch to 30.
    local azimuth is LAZcalc(az_data).   
    lock steering to heading(azimuth, targetPitch).    
  }
  lock throttle to 0.
  print "SECO-1".
  wait 5.
}

function cricularize{
  executeManeuver(time:seconds + eta:apoapsis,0,0,circDeltaV()).
}

function Telemetry{
Print "STARSHIP LAUNCH CONTROL COMPUTER" at ( 2, 1).
Print "-------------------------------------" at ( 2, 2).
Print "____________________________________" at ( 3, 3).
Print "Status: " + ship:status at ( 3, 4).
PRINT "Altitude: " + Alt:radar at (3,5).
Print "Liquide Fule:" + ship:liquidfuel at(3,7).
Print "Oxidizer:" + ship:Oxidizer at(3,8).
}