// This software includes code from KSLib, which is licensed under the MIT license. Copyright (c) 2015-2020 The KSLib team

// ORBIT ANALYTICAL MATHS

function Azimuth {				// azimuth heading for given inclination and target orbit altitude
    parameter tInc, orbitAlt, raw is false, autoSwitch is false.

    local shipLat is ship:latitude.
	local rawHead is 0.		// azimuth without auto switch
    if abs(tInc) < abs(shipLat) { set tInc to shipLat. }
	if (tInc > 180) { set tInc to -360 + tInc. }
	if (tInc < -180) { set tInc to 360 + tInc. }
	if hasTarget { set autoSwitch to true. }

    local head is arcsin(max(min(cos(tInc) / cos(shipLat), 1), -1)).
	set rawHead to head.
	
	if (autoSwitch) {
		if NodeSignTarget() > 0 { set head to 180 - head. }
	}
	else if (tInc < 0) { set head to 180 - head. }

	local eqVel is (2 * constant:pi * body:radius) / body:rotationperiod.
    local vOrbit is sqrt(body:mu / (orbitAlt + body:radius)).
    local vRotX is vOrbit * sin(head) - (eqVel * cos(shipLat)).
    local vRotY is vOrbit * cos(head).
    set head to 90 - arctan2(vRotY, vRotX).
	
	if (raw) { return mod(rawHead + 360, 360). }
	else { return mod(head + 360, 360). }
}

function OrbLAN {				// returns LAN of parameter
	parameter ves is ship.

	if (ves:istype("orbitable")) {
		local spLAN is ves:orbit:lan.
		local bRot is ves:body:rotationangle.
		local bLAN is spLAN - bRot.
		return mod(bLAN, 360).
	}
	else {
		local bLAN is ves - ship:body:rotationangle.
		return mod(bLAN, 360).	// ves in this function returns an orbitable and scalar
	}
}

function GetLNG {				// returns LNG where orbit intersects with latitude
	parameter lat, tInc is 0, tLan is 0.

	if (hasTarget) { 
		set tInc to target:orbit:inclination.
		set tLAN to OrbLAN(target).
	}
	else {
		set tLAN to OrbLAN(tLan).
	}
	
	if (tInc < abs(lat)) {
		if (lat > 0) { set lat to tInc. }
		else { set lat to -tInc. }
	}
	
	local lng0 is arcsin(tan(lat) / tan(tInc)).
	local lngAN is lng0 + tLAN.
	local lngDN is (tLAN - 180) - lng0.
	
	if (lngAN < 0) {
		set lngDN to lngDN + 360.
	}
	
	return list(lngAN, lngDN).
}

function TimeToTgtNode {		// returns time for ship LNG and target node intersection
	parameter lat, lng, tgtSelected is true, tgtInc is 0, tgtLan is 0.
	local rate is body:angularvel:mag * constant:radtodeg.
	local timeAN is 0.
	local timeDN is 0.

	if (tgtSelected) {
		set timeAN to (GetLNG(lat)[0] - lng) / rate.
		set timeDN to (GetLNG(lat)[1] - lng) / rate.
	}
	else {
		set timeAN to (GetLNG(lat, tgtInc, tgtLan)[0] - lng) / rate.
		set timeDN to (GetLNG(lat, tgtInc, tgtLan)[1] - lng) / rate.
	}
	
	if (timeAN < 0) { return list(timeDN, -1). }
	else if (timeDN < timeAN and timeDN > 0) { return list(timeDN, -1). }
	else { return list(timeAN, 1). }
}

function TimeToAltitude {		// returns time to altitude, which ever is closer
    parameter tgtAlt, mode is 0.

    local TA0 is ship:orbit:trueanomaly.
    local ecc is ship:orbit:eccentricity.
	local SMA is ship:orbit:semimajoraxis.

    local ANTA is 0.
    set ANTA to AltToTA(SMA, ecc, ship:body, tgtAlt)[0].
    local DNTA is AltToTA(SMA, ecc, ship:body, tgtAlt)[1].

	// 1 is AN, 2 is DN
	local t0 is time:seconds.
	local MA0 is mod(mod(t0 - ship:orbit:epoch, ship:orbit:period) / ship:orbit:period * 360 + ship:orbit:meananomalyatepoch, 360).

	local EA1 is mod(360 + arctan2(sqrt(1 - ecc^2) * sin(ANTA), ecc + cos(ANTA)), 360).
	local MA1 is EA1 - ecc * constant:radtodeg * sin(EA1).
	local t1 is mod(360 + MA1 - MA0, 360) / sqrt(ship:body:mu / SMA^3) / constant:radtodeg + t0.

	local EA2 is mod(360 + arctan2(sqrt(1 - ecc^2) * sin(DNTA), ecc + cos(DNTA)), 360).
	local MA2 is EA2 - ecc * constant:radtodeg * sin(EA2).
	local t2 is mod(360 + MA2 - MA0, 360) / sqrt(ship:body:mu / SMA^3) / constant:radtodeg + t0.

    if (mode = 0) { return min(t2 - t0, t1 - t0). }
	else if (mode = 1) { return t2 - t0. }
	else { return t1 - t0. }
}

function AltToTA {				// returns true anomalies of the points where the orbit passes the given altitude
	parameter sma, ecc, bodyIn, altIn.
	
	local rad is min(max(ship:orbit:periapsis, altIn), ship:orbit:apoapsis) + bodyIn:radius.
	local TAofAlt is arccos((-sma * ecc^2 + sma - rad) / (ecc * rad)).
	return list(TAofAlt, 360 - TAofAlt). //first true anomaly will be as orbit goes from PE to AP
}




// ORBIT VECTOR MATHS






function NodeAltitude {			// altitude at node
	parameter tNode.
	
	local altAtCloserNode is positionat(ship, time:seconds + tNode).
	return (altAtCloserNode - body:position):mag - body:radius.
}








// LANDING BURN CALCULATION

function LandThrottle {		// throttle for landing

	// Gravity at current altitude
	local gravAcc is body:mu / body:position:sqrmagnitude.

	// Full thrust acceleration — use availableThrustat(0) as fallback during
	// spool-up so we never divide by zero before the engine is lit.
	local thrustEstimate is max(ship:availableThrust, ship:availableThrustat(0)).
	local fullAcc is max(thrustEstimate / ship:mass, 0.1).

	local vertSpd is abs(ship:verticalspeed).
	// Use radar alt (terrain-relative) as base.
	// If Trajectories has an impact point, subtract its terrain height so the
	// stop-distance targets the actual landing elevation, not terrain directly
	// below the ship right now — important during lateral abort landings.
	// alt:radar is already terrain-relative — no correction needed.
	// Use alt:radar (CoM to terrain) — NOT ship:bounds:bottomaltradar.
	// bounds:bottomaltradar measures from the bottom of the bounding box which
	// on a tall rocket is 4-5km below CoM, making throttle fire way too early.
	local radarAlt is max(alt:radar, 1).

	// If moving upward, cut throttle immediately — any thrust makes it worse.
	if (ship:verticalspeed > 0) { return 0. }

	// STOP-DISTANCE THROTTLE:
	// reqDecel = v² / (2 * alt), throttle = (reqDecel + gravAcc) / fullAcc
	// Subtract 20m from radarAlt — the booster CoM is ~20m above the landing legs,
	// so targeting alt=0 means the engine is still burning when legs hit the ground.
	// Targeting alt=20 means the formula reaches zero velocity at leg-contact height.
	local targetAlt is max(radarAlt - 25, 1).
	local reqDecel is (vertSpd^2) / (2 * targetAlt).
	local rawThrottle is (reqDecel + gravAcc) / fullAcc.

	// No safety margin — at near-dry mass TWR~8, even 1.0x is aggressive enough.
	// A margin causes the booster to decelerate too fast then hover on fumes.

	// No floor — throttle goes to zero naturally as velocity bleeds off.
	// Cap at 1.0.
	return max(0, min(1.0, rawThrottle)).
}

function IntegLand {		// landing height check through integration (fixed drag/mass)
	parameter simHeight, 
		simSpeed, 
		isCoreBooster,
		mFlowRate,
		eng,
		thrustGain is 1,
		dist is 0, 
		timestep is 0.1.

	local atmo          is body:atm.
	local atmDensity    is 0.
	local atmPres       is 0.
	local IGMM          is (constant:idealgas / atmo:molarmass) / constant:atmtokpa.
	local engineForce   is 0.
	local dragForce     is 0.
	local gravAcc       is 0.
	local shipMass      is ship:mass.

	// Scale drag area by mass. 0.12 m²/t reflects grid fins deployed during the
	// single-burn descent (previously 0.08 was tuned for post-reentry-burn speeds).
	// Higher drag = IntegLand predicts a slightly later stop = earlier ignition trigger.
	local shipACD       is ship:mass * 0.12.

	// Mass depleted per simulation timestep
	local mFlowPerStep  is mFlowRate * timestep.

	// Fold horizontal distance into effective altitude for accuracy
	set simHeight to sqrt(simHeight^2 + dist^2).

	// simSpeed is NEGATIVE while falling (downward velocity).
	// We integrate until speed reaches 0 (stopped) or height goes below 0 (crashed).
	// Guard simHeight >= 0 to prevent atmo:alttemp(negative) returning 0 → NaN divide.
	local maxSteps is 10000.	// safety cap — prevents infinite loop if physics diverges
	local stepCount is 0.
	until (simSpeed >= 0 or simHeight <= 0 or stepCount > maxSteps) {
		set stepCount to stepCount + 1.

		// Clamp simHeight so atmosphere queries never get a negative altitude
		local safeHeight is max(0, simHeight).

		// Gravity (varies with altitude)
		set gravAcc to body:mu / (body:radius + safeHeight)^2.

		// Atmosphere density via ideal gas law
		set atmPres to atmo:altitudepressure(safeHeight).
		// Guard against alttemp = 0 (at/below ground) to prevent NaN
		local safeTemp is max(1, atmo:alttemp(safeHeight)).
		set atmDensity to atmPres / (IGMM * safeTemp).

		// Drag decelerates the fall (always positive, opposes downward motion)
		set dragForce to 0.2 * atmDensity * simSpeed^2 * shipACD.

		// Engine thrust at current pressure
		set engineForce to eng:availablethrustat(atmPres) * thrustGain.

		// Physics integration:
		// simSpeed is negative (falling). Engine+drag push UP (reduce magnitude).
		// Gravity pulls DOWN (increases magnitude = makes more negative).
		// Net: simSpeed += -(gravAcc) + (engine+drag)/mass   [per timestep]
		set simSpeed  to simSpeed - (gravAcc * timestep) + ((dragForce + engineForce) / shipMass * timestep).
		set simHeight to simHeight + (simSpeed * timestep).

		// Deplete propellant mass
		set shipMass to max(ship:drymass, shipMass - mFlowPerStep).
	}

	// If we hit the ground or overran steps, burn hasn't started early enough
	if (simHeight <= 0 or stepCount > maxSteps) { return true. }	// crashed in sim — burn NOW

	// simHeight is now the altitude where the engine stopped the vehicle.
	// If the stop point is less than 150m above ground, ignite NOW —
	// that is our minimum safe landing cushion.
	// Using a fixed 150m threshold (not a % of radar alt) so it works
	// correctly at all altitudes from 20km down to 100m.
	if (simHeight < 150) { return true. }
	return false.	// stop point is comfortably high — keep waiting
}

// CALCULATED IMPACT ETA

function ImpactUT {			// returns time for ground track prediction
    parameter minError is 1.
	
	if not (defined impact_UTs_impactHeight) { global impact_UTs_impactHeight is 0. }
	local startTime is time:seconds.
	local craftOrbit is ship:orbit.
	local sma is craftOrbit:semimajoraxis.
	local ecc is craftOrbit:eccentricity.
	local craftTA is craftOrbit:trueanomaly.
	local orbitperiod is craftOrbit:period.
	local ap is craftOrbit:apoapsis.
	local pe is craftOrbit:periapsis.
	local impactUTs is TimeTwoTA(ecc,orbitperiod,craftTA,AltToTA(sma,ecc,ship:body,max(min(impact_UTs_impactHeight,ap - 1),pe + 1))[1]) + startTime.
	local newImpactHeight is max(0, GroundTrack(positionat(ship,impactUTs),impactUTs):terrainheight).
	set impact_UTs_impactHeight TO (impact_UTs_impactHeight + newImpactHeight) / 2.
	
	return lex("time",impactUTs,//the UTs of the ship's impact
		"impactHeight",impact_UTs_impactHeight,//the aprox altitude of the ship's impact
		"converged",((ABS(impact_UTs_impactHeight - newImpactHeight) * 2) < minError)).//will be true when the change in impactHeight between runs is less than the minError
}

function TimeTwoTA {		// returns the difference in time between 2 true anomalies, traveling from taDeg1 to taDeg2
	parameter ecc,periodIn,taDeg1,taDeg2.
	
	local maDeg1 is TrueAToMeanA(ecc,taDeg1).
	local maDeg2 is TrueAToMeanA(ecc,taDeg2).
	
	local timeDiff is periodIn * ((maDeg2 - maDeg1) / 360).
	
	return mod(timeDiff + periodIn, periodIn).
}

function TrueAToMeanA {		// true anomaly to mean anomaly
	parameter ecc,taDeg.
	
	local eaDeg is arctan2(sqrt(1-ecc^2) * sin(taDeg), ecc + cos(taDeg)).
	local maDeg is eaDeg - (ecc * sin(eaDeg) * constant:radtodeg).
	return mod(maDeg + 360, 360).
}

function GroundTrack {		// impact point through orbit prediction
	parameter pos, posTime, localBody is ship:body.
	
	local bodyNorth is v(0,1,0).
	local rotationalDir is vdot(bodyNorth,localBody:angularvel) * constant:radtodeg.
	local posLATLNG is localBody:geopositionof(pos).
	local timeDif is posTime - time:seconds.
	local longitudeShift is rotationalDir * timeDif.
	local newLNG is mod(posLATLNG:lng + longitudeShift,360).
	if (newLNG < - 180) { set newLNG TO newLNG + 360. }
	if (newLNG > 180) { set newLNG TO newLNG - 360. }
	
	return latlng(posLATLNG:lat, newLNG).
}

function Impact {			// ground track and trajectories
    parameter nav, lP, LZ.	// return type, landProfile

    local impData is 0.
	local impLatLng0 is 0.
	local impLatLng1 is 0.
	local landToBody is 0.
	local dRange is 0.
	local LZToBody is body:position - LZ:altitudeposition(0).
	
    if (addons:tr:hasimpact and lP < 3) {
        set impLatLng1 to addons:tr:impactpos.
			
		if (nav = 0) { return impLatLng1. }
		else { 
			set landToBody to body:position - impLatLng1:altitudeposition(0).
			set dRange to (vang(landToBody, LZToBody) / 360) * (2 * constant:pi * body:radius).
			return dRange.  
		}
    } 
	else {
		set impData to ImpactUT().
		set impLatLng0 to GroundTrack(positionat(ship,impData["time"]),impData["time"]).
       
	    if (nav = 0) { return impLatLng0. }
        else { 
			set landToBody to body:position - impLatLng0:altitudeposition(0).
			set dRange to (vang(landToBody, LZToBody) / 360) * (2 * constant:pi * body:radius).
			return dRange.  
		}
    }
}

// CRAFT SYSTEMS / UTILITIES

function Prt {
	parameter textInput.

	local met is time(missionTime):clock.
	print "[" + met + "]: " + textInput.
}

function SafeStage {		// avoid staging when unfocused

	if (ship = kuniverse:activevessel and stage:ready) { stage. }  
}

function EngSpl {			// engine spool function
	parameter tgt, ullage is false.
	
	local startTime is time:seconds.
	
    if (ullage) { 
        rcs on. 
        set ship:control:fore to 0.75.
        
        when (time:seconds > startTime + 2) then { 
            set ship:control:neutralize to true. rcs off. 
        }
    }
	
	if (throt < tgt) {
		if (ullage) { set throt to 0.025. wait 0.5. }	// TEA-TEB
		until (throt >= tgt) {
			set throt to throt + (DeltaTime() * 1.333).
		}
	}
	else {
		until (throt <= tgt) { 
			set throt to throt - (DeltaTime() * 1.333).
		}
	}
	
	set throt to tgt.
}

function DeltaTime {		// returns deltaTime
	local startTime is time:seconds. wait 0.
	return time:seconds - startTime.
}

function LinEq {			// linear equation function
	parameter var, x2, y1, y2, x1 is 0.
	// y = mx + b
	
	return ((y2 - y1) / (x2 - x1)) * var + (((x2 * y1) - (x1 * y2)) / (x2 - x1)).
}

function BetterWarp {		// better warp mode that avoids overshoots
	parameter duration, disp is false.

	local safe_margin is 1.
	
	local startT is time:seconds.
	local endT is startT + duration.
	lock remainT to endT - time:seconds.
	
	set kuniverse:timewarp:mode to "rails".
	
	local minimumT is 	list(0, 10, 100, 1000, 10000, 100000, 1000000, (remainT + 1)).
	local multiplier is list(1, 10, 100, 1000, 10000, 100000, 1000000, 10000000).
	
	local done is false.
	until (remainT <= 10 or done) {

		local warpLevel is 0.
		
		until ((warpLevel >= minimumT:length) or (minimumT[warpLevel + 1] > remainT)) {
			set warpLevel to warpLevel + 1. wait 0.
			set kuniverse:timewarp:warp to warpLevel.
		}
		
		local margin is safe_margin * multiplier[warpLevel].
		if (remainT < margin) { set done to true. }
		until (remainT < margin) {
			if (launchButton:pressed and loadButton:pressed) { 
				set kuniverse:timewarp:warp to 0.
				kuniverse:timewarp:cancelwarp().
				wait until kuniverse:timewarp:issettled.
				set launchButton:text to "SCRUBBED". 
				set launchButton:enabled to false.
				wait 10. reboot. 
				}
			else {
				if (disp) { set launchButton:text to "T: -" + timestamp(remainT):clock. }
			}
		}
	}
	
	set kuniverse:timewarp:warp to 0.
	until (remainT < 0 or remainT = 0) { 
		if (disp) { set launchButton:text to "T: -" + timestamp(remainT):clock. } 
	} .
	kuniverse:timewarp:cancelwarp().
    until kuniverse:timewarp:issettled {
		if (disp) { set launchButton:text to "T: -" + timestamp(remainT):clock. }
	}
}

function SecToDay {			// converts seconds to days
	parameter secVal.
	
	local hpd is kuniverse:hoursperday.
	return (secVal / hpd / 3600).
}

function DayToSec {			// converts days to sec
	parameter dayVal.
	
	local hpd is kuniverse:hoursperday.
	return (dayVal * hpd * 3600).
}






// RSVP SCHEDULER AND EVALUATOR





// HILLCLIMBING ALGORITHM




