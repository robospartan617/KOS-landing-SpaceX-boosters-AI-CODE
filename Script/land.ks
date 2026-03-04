//Creator: Kerbal Gamer
//Credits: Edvin Robert

runOncePath("0:/My_Lib.ks").
//Landing Settings
set boosterHeight to 80.
set entryBurnAlt to 35000.
set entryBurnShutdownVel to -340.
set MaxLandingBurnStartAlt to 4000.
set landingPad to latlng(-0.0972224543225299,-74.5577919169731).

//PID Values (This is the max I could get, if u can tune it better pls send the PID values to me on discord)
set VelKp to 1355.
set VelKi to 3.
set VelKd to 763.

set PosKi to 0.01.
set PosKd to 100.

//Suicide Burn Calculations
set radarOffset to boosterHeight + 4.
lock trueRadar to alt:radar - radarOffset.                    
lock g to constant:g * body:mass / body:radius^2.            
lock maxDecel to (ship:availablethrust / ship:mass) - g.    
lock stopDist to ship:verticalspeed^2 / (2 * maxDecel).        
lock idealThrottle to stopDist / trueRadar.  
set aoa to 30. 

//Steering Manager 
set steeringManager:maxstoppingtime to 0.25.
set steeringManager:rollts to 50.

//Before Entry Burn 
Rcs on.
lock steering to up.
brakes on.
wait until alt:radar < entryBurnAlt + 5000.
lock steering to srfretrograde.

wait until alt:radar < entryBurnAlt.//Entry Burn Start up
lock throttle to 1.
lock steering to Land_steering().
set aoa to 0.


wait until ship:verticalspeed > entryBurnShutdownVel.
lock throttle to 0.
set aoa to 35.
setEngineThrustLimit("S1 eng",80).

wait until alt:radar < 7000.
set aoa to 15.
//rcs off.

wait until alt:radar < MaxLandingBurnStartAlt.
//does nothing here 

wait until trueRadar <= stopDist.
set steeringManager:maxstoppingtime to 0.65.
lock throttle to (idealThrottle+ 0.1).
setEngineThrustLimit("S1 eng",100).

Set_landing_Pid_Settings().
lock aoa to -2.
rcs on.
wait until alt:radar < 400.
setHoverDescendSpeed(10).
setHoverMaxSteerAngle(4).

until  alt:Radar <= 300{
	updateHoverSteering().
	}
toggle ag1. 

until ship:verticalspeed > -0.5{
	local impactDist is calcDistance(LandingPad, ship:geoposition).

    updateHoverSteering().
	setHoverMaxSteerAngle(3).
 	 if alt:radar < 80{
		lock STEERING TO heading(90,90).
		setHoverDescendSpeed(3).
	    steeringManager:resettodefault().
		
		
	}
    if alt:radar < 90 and impactDist < 10 {
     sendCommToVessel(vessel("Mechazilla"),"Close arms").
	 brakes off.
	}
}

lock steering to up.
set ship:control:pilotmainthrottle to 0.
wait 5.
shutdown.
//Functions
function Impact_Pos{
    return getImpact():position - landingPad:position.
}

function Land_steering {
    local errorVector is Impact_Pos().
        local velVector is -ship:velocity:surface.
        local result is velVector + errorVector*1.
        if vang(result, velVector) > aoa
        {
            set result to velVector:normalized
                          + tan(aoa)*errorVector:normalized.
        }
       return lookdirup(result, facing:topvector).
}

function calcDistance { //Approx in meters
	parameter geo1.
	parameter geo2.
	return (geo1:POSITION - geo2:POSITION):MAG.
}
function DistToTarget{
parameter Targ.
return calcDistance(targ, getImpact()).
}

function Set_landing_Pid_Settings{
setHoverPIDLOOPS().
setHoverMaxSteerAngle(8).
setHoverMaxHorizSpeed(4).
setHoverTarget(landingPad:lat,landingPad:lng).
setHoverAltitude(-100).
} 

function setHoverPIDLOOPS{
	//Controls altitude by changing HoverPID setpoint
	SET hoverPID TO PIDLOOP(1, 0.01, 0.0, -50, 50). 
	//Controls vertical speed by changing the Climb PID setpoint
	SET climbPID TO PIDLOOP(0.1, 0.3, 0.005, 0,1). 	

SET eastVelPID TO PIDLOOP(VelKp, VelKi, VelKd, -35, 35). //Controls horizontal speed by tilting rocket
SET northVelPID TO PIDLOOP(VelKp, VelKi, VelKd, -35, 35).
SET eastPosPID TO PIDLOOP(1700, PosKi , PosKd, -40, 40). //controls horizontal position by changing velPID setpoints
SET northPosPID TO PIDLOOP(1700, PosKi , PosKd, -40, 40).
}

function setHoverDescendSpeed{
	parameter a.
	SET hoverPID:MAXOUTPUT TO a.
	SET hoverPID:MINOUTPUT TO -1*a.
	SET climbPID:SETPOINT TO hoverPID:UPDATE(TIME:SECONDS, SHIP:ALTITUDE). //control descent speed with throttle
	lock throttle TO climbPID:UPDATE(TIME:SECONDS, SHIP:VERTICALSPEED).	
}
function setHoverAltitude{ //set just below landing altitude to touchdown smoothly
	parameter a.
	SET hoverPID:SETPOINT TO a.
}

function setThrottleSensitivity{
	parameter a.
	SET climbPID:KP TO a.
}

function sProj { //Scalar projection of two vectors.
	parameter a.
	parameter b.
	if b:mag = 0 {  RETURN 1. }
	RETURN VDOT(a, b) * (1/b:MAG).
}

function cVel {
	local v IS SHIP:VELOCITY:SURFACE.
	local eVect is VCRS(UP:VECTOR, NORTH:VECTOR).
	local eComp IS sProj(v, eVect).
	local nComp IS sProj(v, NORTH:VECTOR).
	local uComp IS sProj(v, UP:VECTOR).
	RETURN V(eComp, uComp, nComp).
}

function updateHoverSteering{
	SET cVelLast TO cVel().
	SET eastVelPID:SETPOINT TO eastPosPID:UPDATE(TIME:SECONDS, Ship:geoposition:LNG).
	SET northVelPID:SETPOINT TO northPosPID:UPDATE(TIME:SECONDS, ship:geoposition:LAT).
	LOCAL eastVelPIDOut IS eastVelPID:UPDATE(TIME:SECONDS, cVelLast:X).
	LOCAL northVelPIDOut IS northVelPID:UPDATE(TIME:SECONDS, cVelLast:Z).
		
	LOCAL eastPlusNorth is MAX(ABS(eastVelPIDOut), ABS(northVelPIDOut)).//SQRT(eastVelPIDOut^2 + northVelPIDOut^2). 
	SET steeringPitch TO 90 - eastPlusNorth.
	LOCAL steeringDirNonNorm IS ARCTAN2(eastVelPID:OUTPUT, northVelPID:OUTPUT). //might be negative
	if steeringDirNonNorm >= 0 {
		SET steeringDir TO steeringDirNonNorm.
	} else {
		SET steeringDir TO 360 + steeringDirNonNorm.
	}
	LOCK STEERING TO HEADING(steeringDir,steeringPitch).
}
function setHoverTarget{
	parameter lat.
	parameter lng.
	SET eastPosPID:SETPOINT TO lng.
	SET northPosPID:SETPOINT TO lat.
}


function setHoverMaxSteerAngle{
	parameter a.
	SET eastVelPID:MAXOUTPUT TO a.
	SET eastVelPID:MINOUTPUT TO -1*a.
	SET northVelPID:MAXOUTPUT TO a.
	SET northVelPID:MINOUTPUT TO -1*a.
}
function setHoverMaxHorizSpeed{
	parameter a.
	SET eastPosPID:MAXOUTPUT TO a.
	SET eastPosPID:MINOUTPUT TO -1*a.
	SET northPosPID:MAXOUTPUT TO a.
	SET northPosPID:MINOUTPUT TO -1*a.
}