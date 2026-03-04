// BOOSTER.ks — SpaceX-style booster landing script
// Fixes: drag/mass simulation, LZ coords, revert safety,
//        gear deploy, orientation, infinite loops, game freeze

clearscreen.

// ── SAFETY: detect revert/destruction and self-terminate ──────────────────
// kOS has no revert hook, but we detect it: if the active vessel changes
// (revert replaces it) or the ship is destroyed, we clean up and die.
when (ship:status = "DEAD" or
      kuniverse:activevessel:name <> ship:name) then {
    print "ABORT: vessel lost or reverted.".
    unlock steering. unlock throttle.
    set ship:control:neutralize to true.
    // do NOT requeue - trigger fires once and stops
}

// ── PERFORMANCE: raise IPU to prevent game freeze ─────────────────────────
// Default 200 IPU causes KSP to stall during heavy computation.
// 800 is a safe balance between script speed and game framerate.
set config:ipu to 800.

// ── KSC LAUNCHPAD COORDINATES ─────────────────────────────────────────────
// lat -0.0972, lng -74.5757  (KSC Launch Pad 1, Kerbin)
// Used as fallback if params2.json is missing or has no LZ keys.
local KSC_LZ is latlng(-0.0972, -74.5757).

// ── GLOBALS ───────────────────────────────────────────────────────────────
local padPos          is ship:position.
local rotOffset       is 0.
local overshootCoords is 0.
local overshootVector is v(0,0,0).
local reduceLateral   is v(0,0,0).
local osGain          is 1.
local forceThree      is false.
local initVec         is ship:facing:forevector.
local flipVec         is ship:facing:forevector.

// ── MAIN SEQUENCE ─────────────────────────────────────────────────────────
WaitForSep().
runoncepath("0:/COMMON/GNC").

// ── LOAD MISSION PARAMS ───────────────────────────────────────────────────
local pLex is lexicon(
    "landProfile",    0,
    "maxPayload",     10000,
    "MECOangle",      0,
    "payloadMass",    0,
    "reentryHeight",  30000,
    "reentryVelocity",500,
    "LZ0",            KSC_LZ,
    "LZ1",            KSC_LZ,
    "LZ2",            KSC_LZ
).
if exists("0:/params2.json") {
    set pLex to readjson("0:/params2.json").
} else {
    print "WARNING: params2.json missing - defaulting LZ to KSC launchpad.".
}

// Ensure LZ keys exist even if params file was old/incomplete
if not pLex:haskey("LZ0") { pLex:add("LZ0", KSC_LZ). }
if not pLex:haskey("LZ1") { pLex:add("LZ1", KSC_LZ). }
if not pLex:haskey("LZ2") { pLex:add("LZ2", KSC_LZ). }

local flightSave is lexicon("tgtAzimuth", 90, "tgtRotation", 0).
if (core:tag = "2" or core:tag = "3") {
    if exists("0:/params4.json") { set flightSave to readjson("0:/params4.json"). }
    else { print "WARNING: params4.json missing - using defaults.". }
} else {
    if exists("0:/params3.json") { set flightSave to readjson("0:/params3.json"). }
    else { print "WARNING: params3.json missing - using defaults.". }
}

local landProfile     is pLex["landProfile"].
local maxPayload      is pLex["maxPayload"].
local MECOangle       is pLex["MECOangle"].
local payloadMass     is pLex["payloadMass"].
local reentryHeight   is pLex["reentryHeight"].
local reentryVelocity is pLex["reentryVelocity"].
local tgtAzimuth      is flightSave["tgtAzimuth"].
local tgtRotation     is flightSave["tgtRotation"].

// ── LANDING ZONE SELECTION ────────────────────────────────────────────────
local LZ is KSC_LZ.
if      (landProfile = 1 or core:tag = "3") { set LZ to pLex["LZ1"]. }
else if (core:tag = "2")                    { set LZ to pLex["LZ2"]. }
else                                        { set LZ to pLex["LZ0"]. }
print "LZ: " + round(LZ:lat,4) + " / " + round(LZ:lng,4).

set throt to 0.
lock throttle to throt.
if (landProfile = 6) { shutdown. }

PIDsetup().

if (landProfile = 1 or
    ((core:tag = "2" or core:tag = "3") and
    (landProfile = 4 or landProfile = 5))) {
    Flip1(180, 0.333).
    Boostback().
    Flip2(60, 0.0667).
    Reentry1(60).
} else {
    Flip1(170, 0.333).
    Boostback(5).
    Flip2(45, 0.075).
    Reentry1(45).
}

AtmGNC().
Land().

AG10 off.
shutdown.
set core:bootfilename to "".

// ═════════════════════════════════════════════════════════════════════════
// FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════

// ── WAIT FOR STAGE SEPARATION ─────────────────────────────────────────────
function WaitForSep {
    local coreList is list().
    list processors in coreList.
    local initCoreCount  is coreList:length.
    local currCoreCounts is initCoreCount.
    list engines in engList.
    local currEngCounts  is engList:length.

    until (
        (core:tag = "1" and currCoreCounts < initCoreCount) or
        ((core:tag = "2" or core:tag = "3") and currCoreCounts = 1)
    ) {
        set initVec  to ship:facing:forevector.
        set flipVec  to ship:facing:forevector.
        list processors in coreList.
        set currCoreCounts to coreList:length.
        list engines in engList.
        set currEngCounts  to engList:length.
        wait 0.1.
    }

    print "Separation detected.".
    core:part:controlfrom().
    wait 2.
    // Refresh after controlfrom() resets the reference frame
    set initVec to ship:facing:forevector.
    set flipVec to ship:facing:forevector.
}

// ── FLIP 1: Engines-down post-sep flip ────────────────────────────────────
function Flip1 {
    parameter finalAttitude, flipPower.

    kuniverse:timewarp:cancelwarp().
    set steeringmanager:maxstoppingtime to 3. rcs on.
    set steeringmanager:pitchts        to (steeringmanager:pitchts * 1.5).
    set steeringmanager:yawts          to (steeringmanager:yawts * 1.5).
    set steeringmanager:pitchpid:ki    to (steeringmanager:pitchpid:ki * 1.5).
    set steeringmanager:yawpid:ki      to (steeringmanager:yawpid:ki * 1.5).
    set steeringmanager:rolltorquefactor to 3.
    set steeringmanager:rollcontrolanglerange to 45.

    lock steering to lookdirup(
        heading(tgtAzimuth, MECOangle):vector,
        (heading(180, 0):vector * ((180 + tgtRotation) / 180)) +
        (vcrs(heading(tgtAzimuth, MECOangle):vector,
             heading(tgtAzimuth, 0):vector) * (abs(tgtRotation) / 180))
    ).
    wait 2.
    EngSwitch(0, 1).
    unlock steering.

    local rotateOffset is 45.
    local tangentVector is vxcl(up:vector, srfretrograde:vector:normalized):normalized.
    local rotateVector  is vcrs(tangentVector, body:position:normalized):normalized.
    local finalVector   is (-tangentVector * angleAxis(finalAttitude, rotateVector)):normalized.

    lock steering to lookdirup(flipVec, -rotateVector).

    if (core:tag = "2" or core:tag = "3") {
        local startT is time:seconds.
        local timer  is startT + 2.
        until (vang(ship:facing:topvector, vxcl(ship:facing:forevector, -rotateVector)) < 1
               and time:seconds > timer) { wait 0. }
    }

    // Coarse flip — timeout prevents infinite loop
    local flipTimeout is time:seconds + 60.
    until (vang(finalVector, flipVec) < 25 or time:seconds > flipTimeout) { wait 0.
        if (vang(ship:facing:forevector, flipVec) < 7.5) {
            set flipVec to flipVec * angleAxis(flipPower, rotateVector).
        }
    }
    // Fine flip
    set flipTimeout to time:seconds + 30.
    until (vang(finalVector, flipVec) < 15 or time:seconds > flipTimeout) { wait 0.
        set flipVec to flipVec * angleAxis(flipPower, rotateVector).
    }

    set rotateOffset to finalAttitude.
    set flipVec to -tangentVector * angleAxis(rotateOffset, rotateVector).
    if (core:tag = "2" or core:tag = "3") { toggle AG3. }
    lock steering to lookdirup(flipVec, -rotateVector).
    EngSpl(1).
}

// ── BOOSTBACK BURN ────────────────────────────────────────────────────────
function Boostback {
    parameter rotateOffset is 0.

    if (rotateOffset > 0) { set rotOffset to rotateOffset. }
    steeringmanager:resettodefault().
    set steeringmanager:maxstoppingtime to 15.
    set steeringmanager:rollts to 20.

    local tangentVector is vxcl(up:vector, srfretrograde:vector):normalized.
    local rotateVector  is vcrs(tangentVector, body:position:normalized):normalized.
    clearscreen. rcs off.

    if (landProfile = 1 or core:tag = "2" or core:tag = "3") {
        lock steering to lookdirup(
            vxcl(up:vector, ship:srfretrograde:vector:normalized):normalized *
            angleAxis(0, ship:facing:topvector), -rotateVector).
        local cancelTimeout is time:seconds + 45.
        until (vxcl(up:vector, ship:srfretrograde:vector:normalized):mag <= 0.03
               or time:seconds > cancelTimeout) { wait 0. }
    } else {
        lock steering to lookdirup(
            vxcl(up:vector, ship:srfretrograde:vector:normalized):normalized *
            angleAxis(rotateOffset, ship:facing:topvector), -rotateVector).
    }

    EngSpl(1). rcs on.

    if (landProfile = 1 or core:tag = "2" or core:tag = "3") {
        lock throt to min(max(0.125, Impact(1, landProfile, LZ) / 2), 1).
        lock BBvec to vxcl(up:vector, LZ:altitudeposition(ship:altitude)):normalized.
        lock steering to lookdirup(BBvec, ship:facing:topvector).

        local landingOvershoot is 0.	// zero overshoot - AtmGNC PID handles all lateral correction
        local impDist is Impact(1, landProfile, LZ).
        local intDist is max(impDist, 1).
        local bbTimeout is time:seconds + 120.

        until (impDist < landingOvershoot or time:seconds > bbTimeout) {
            local bodPos    is body:position.
            local landAngle is vang(bodPos, vxcl(rotateVector, Impact(0, landProfile, LZ):position)).
            local LZAngle   is vang(bodPos, vxcl(rotateVector, LZ:position)).
            if (landAngle > LZAngle) { set impDist to -Impact(1, landProfile, LZ). }
            else                     { set impDist to  Impact(1, landProfile, LZ). }
            wait 0.
            set throt to max(0.25, impDist / intDist).
        }
    } else {
        local tempLZ is LZ.
        local landingOvershoot is 0.	// zero overshoot - AtmGNC PID handles all lateral correction
        set LZ to body:geopositionof(LZ:position + ((padPos - LZ:position):normalized * -landingOvershoot)).
        local intDist   is max(Impact(1, landProfile, LZ), 1).
        local bbTimeout is time:seconds + 120.

        until ((Impact(0, landProfile, LZ):position - padPos):mag < (LZ:position - padPos):mag
               or time:seconds > bbTimeout) {
            wait 0.
            set throt to max(0.125, Impact(1, landProfile, LZ) / intDist).
        }
        set LZ to tempLZ.
        lock steering to lookdirup(
            vxcl(up:vector, ship:srfretrograde:vector:normalized):normalized *
            angleAxis(rotateOffset, ship:facing:topvector), -rotateVector).
    }

    EngSpl(0).
    wait 1.
    steeringmanager:resettodefault().
}

// ── FLIP 2: Flip to reentry attitude ──────────────────────────────────────
function Flip2 {
    parameter finalAttitude, flipPower.

    set steeringmanager:maxstoppingtime to 20.
    set steeringmanager:rollts to 20.
    set steeringmanager:rolltorquefactor to 0.5.
    wait 2. unlock steering.

    local tangentVector is vxcl(up:vector, srfretrograde:vector:normalized):normalized.
    local fv2           is -tangentVector.
    local rotateVector  is vcrs(tangentVector, body:position:normalized):normalized.
    local finalVector   is (fv2 * angleAxis(180 - finalAttitude, rotateVector)):normalized.

    if (landProfile = 1 or core:tag = "2" or core:tag = "3") {
        lock steering to lookdirup(fv2, rotateVector).
        when (vang(up:vector, ship:facing:forevector) < 15) then { brakes on. }
        local t2 is time:seconds + 60.
        until (vang(finalVector, fv2) < 1 or time:seconds > t2) { wait 0.
            set fv2 to fv2 * angleAxis(flipPower, rotateVector).
        }
        set fv2 to (-tangentVector) * angleAxis(180 - finalAttitude, rotateVector).
        lock steering to lookdirup(
            heading(tgtAzimuth, finalAttitude):vector,
            heading(90 + tgtAzimuth, 0):vector).
    } else {
        set fv2 to fv2 * angleAxis(-rotOffset, rotateVector).
        set fv2 to -fv2.
        lock steering to lookdirup(fv2, -rotateVector).
        local t2 is time:seconds + 60.
        until (vang(finalVector, fv2) < 1 or time:seconds > t2) { wait 0.
            set fv2 to fv2 * angleAxis(-flipPower, rotateVector).
        }
        set fv2 to tangentVector * angleAxis(finalAttitude, -rotateVector).
        brakes on.
        lock steering to lookdirup(
            heading(180 + tgtAzimuth, finalAttitude):vector,
            heading(90 + tgtAzimuth, 0):vector).
    }

    wait 10.
    steeringmanager:resettodefault().
    // Do NOT turn sas on here — Reentry1 immediately locks steering to srfretrograde.
    // sas on would fight that lock and cause the booster to tumble.
    unlock steering.
}

// ── REENTRY BURN ──────────────────────────────────────────────────────────
function Reentry1 {
    parameter holdAngle.

    // The booster must be engines-first (srfretrograde) throughout reentry.
    // Do NOT wait with SAS holding an arbitrary attitude — lock steering immediately.
    // srfretrograde on a descending, engines-first booster = nose pointing up = correct.
    steeringmanager:resettodefault().
    set steeringmanager:maxstoppingtime to 10.
    sas off.

    // Lock to srfretrograde RIGHT NOW so the booster stays stable during the arc.
    // heading(180,0) as up-vector keeps the roll axis pointing south = consistent roll reference.
    lock steering to lookdirup(
        ship:srfretrograde:vector:normalized,
        heading(180, 0):vector).

    brakes on.   // Grid fins deploy
    toggle AG2.

    if (landProfile = 4 and core:tag = "1") {
        set reentryHeight   to reentryHeight + 5000.
        set reentryVelocity to reentryVelocity * 1.5.
    }

    // Wait until booster has arced enough that srfretrograde is steep (engines-down).
    // rtrDiff = how many degrees the retrograde vector is above the horizon.
    // holdAngle = 45 or 60 deg — wait until falling steeply enough for a clean reentry.
    // Steering is LOCKED the whole time so booster tracks srfretrograde continuously.
    local rtrDiff is 0.
    local t1 is time:seconds + 180.
    until (rtrDiff >= holdAngle or time:seconds > t1) { wait 0.
        set rtrDiff to 90 - vang(ship:up:vector:normalized, ship:srfretrograde:vector:normalized).
    }

    local altTarget is reentryHeight + ((maxPayload - payloadMass) / 7).
    local t2 is time:seconds + 300.
    until (alt:radar < altTarget or time:seconds > t2) { wait 0. }

    EngSpl(1).

    local velTarget is reentryVelocity - ((maxPayload - payloadMass) / 35).
    local t3 is time:seconds + 60.
    until (ship:airspeed < velTarget or time:seconds > t3) { wait 0. }
    EngSpl(0).
}

// ── ATMOSPHERIC GNC ───────────────────────────────────────────────────────
function AtmGNC {
    EngSwitch(1, 2).

    lock LATvector to vxcl(up:vector, (
        latlng(ship:geoposition:lat - 0.01, ship:geoposition:lng):position
        )):normalized.
    lock LNGvector to vxcl(up:vector, (
        latlng(ship:geoposition:lat, ship:geoposition:lng + 0.01):position
        )):normalized.
    // srfretrograde on descent = pointing away from ground = nose up, engines down = correct
    lock RTRvector to ship:srfretrograde:vector:normalized.

    local initAlt  is ship:altitude.
    local finalAlt is initAlt - 7500.
    // Guard against divide-by-zero if booster enters AtmGNC at low altitude
    local lerpDenom is max(initAlt - finalAlt, 1).
    lock lerpToSetpoint to (initAlt - min(initAlt, max(finalAlt, ship:altitude))) / lerpDenom.

    AlatPID:reset(). AlngPID:reset().
    lock overshootVector to (LZ:altitudeposition(0) - ship:geoPosition:altitudeposition(0)).
    lock overshootCoords to ship:body:geopositionof(LZ:altitudeposition(0) + overshootVector).
    lock reduceLateral   to vcrs(body:position, vxcl(up:vector, overshootVector:normalized)):normalized.

    lock steering to lookdirup(
        (RTRvector +
         ((ship:facing:starvector * (ship:facing:starvector *
           ((vcrs(RTRvector, LNGvector) * AlatOut * lerpToSetpoint) +
            (vcrs(RTRvector, LATvector) * AlngOut * lerpToSetpoint))))
          + (ship:facing:topvector * (ship:facing:topvector *
           ((vcrs(RTRvector, LNGvector) * AlatOut * lerpToSetpoint) +
            (vcrs(RTRvector, LATvector) * AlngOut * lerpToSetpoint)))))
         - (0.5 * reduceLateral * (reduceLateral *
           ((vcrs(RTRvector, LNGvector) * AlatOut * lerpToSetpoint) +
            (vcrs(RTRvector, LATvector) * AlngOut * lerpToSetpoint))))),
        LATvector).

    rcs on.
    when (ship:altitude < 11000) then { rcs off. }

    local isCoreBooster is 1.
    if (core:tag = "2" or core:tag = "3") { set isCoreBooster to 0. }
    if (payloadMass > maxPayload or landProfile > 3) { set forceThree to true. }
    local thrustGain is 1.
    if (landProfile > 3 or forceThree) { set thrustGain to 1.5. }

    list engines in engList.

    // Do NOT index by isCoreBooster — after sep/reentry the list size varies.
    // Find the center engine (lowest thrust = center on Falcon 9 = landing engine)
    // by picking the engine with the lowest available thrust among active engines.
    // Fallback: use first engine in list if none are ignited yet.
    local eng is engList[0].
    local lowestThrust is eng:availablethrustat(1) + 1.
    for e in engList {
        if e:availablethrustat(1) < lowestThrust {
            set lowestThrust to e:availablethrustat(1).
            set eng to e.
        }
    }
    local mFlowRate is eng:availablethrustat(1) / (eng:ispat(1) * constant:g0).

    // ── ABORT MONITORING ─────────────────────────────────────────────────
    // Track whether we are converging on the LZ or diverging.
    // If diverging for too long at low altitude, abort to nearest safe spot.
    local prevDistToLZ   is 9e9.
    local divergeStartT  is -1.      // timestamp when divergence began (-1 = not diverging)
    local abortLanding   is false.
    local DIVERGE_LIMIT  is 12.      // seconds of continuous divergence before abort
    local ABORT_MIN_ALT  is 8000.    // only trigger abort below this altitude
    local LOW_FUEL_FRAC  is 0.06.    // abort if <6% fuel and still far from LZ

    // Loop exits when IntegLand says burn now, or as safety at 500m
    until (alt:radar < 500) {
        local overshootQ is max(0, min(0.5, ship:q - 0.15)).
        local altvelOS   is overshootAlt + overshootQ.
        set AlatPID:setpoint to ((1 - altvelOS) * LZ:lat) + (altvelOS * overshootCoords:lat).
        set AlngPID:setpoint to ((1 - altvelOS) * LZ:lng) + (altvelOS * overshootCoords:lng).
        local distToLZ is Impact(1, landProfile, LZ).
        print "Alt: " + round(alt:radar) + "  LZ dist: " + round(distToLZ) + "m  VS: " + round(ship:verticalspeed) at (0,3).

        // ── ABORT CONDITION A: LZ distance growing at low altitude ────────
        if (alt:radar < ABORT_MIN_ALT) {
            if (distToLZ > prevDistToLZ + 5) {
                // Getting farther from LZ this tick
                if (divergeStartT < 0) { set divergeStartT to time:seconds. }
                if (time:seconds - divergeStartT > DIVERGE_LIMIT) {
                    set abortLanding to true.
                }
            } else {
                set divergeStartT to -1.   // reset — we are converging again
            }
        }
        set prevDistToLZ to distToLZ.

        // ── ABORT CONDITION B: critically low fuel, still far from LZ ────
        local fuelFrac is ship:liquidfuel / max(ship:drymass * 50, 1).
        if (fuelFrac < LOW_FUEL_FRAC and distToLZ > 800) {
            set abortLanding to true.
        }

        // ── ABORT CONDITION C: manual abort via AG9 ───────────────────────
        if (ag9) { set abortLanding to true. }

        // ── ABORT HANDLER ─────────────────────────────────────────────────
        if (abortLanding) {
            AbortToNearest().
            // AbortToNearest redirects LZ to current position and resets PIDs.
            // After this, the loop continues normally — just aiming somewhere safe.
            set abortLanding to false.
            set divergeStartT to -1.
        }

        if (IntegLand(alt:radar, ship:verticalspeed, isCoreBooster,
                      mFlowRate, eng, thrustGain, distToLZ, 0.2)) { break. }
        wait 0.
    }

    print "IGNITION at " + round(alt:radar) + "m / " + round(ship:verticalspeed) + "m/s" at (0,5).
    EngSpl(1).
    set throt to 1.
}

// ── ABORT TO NEAREST SAFE LANDING SPOT ───────────────────────────────────
// Called when the booster cannot reach its target LZ.
// Redirects the LZ target to the current predicted impact point
// so the booster lands straight down from where it is.
// Does NOT disrupt Land() or IntegLand — they are altitude/speed only.
function AbortToNearest {
    // Predicted ground impact point at current trajectory
    local impactPos is Impact(0, landProfile, LZ).

    // Switch LZ to the impact point — booster now aims to land right there
    set LZ to impactPos.

    // Reset PID controllers so they don't carry over the old LZ error
    AlatPID:reset(). AlngPID:reset().
    HlatPID:reset(). HlngPID:reset().
    set AlatPID:setpoint to LZ:lat.
    set AlngPID:setpoint to LZ:lng.
    set HlatPID:setpoint to LZ:lat.
    set HlngPID:setpoint to LZ:lng.

    // Repoint overshoot vectors to new LZ
    lock overshootVector to (LZ:altitudeposition(0) - ship:geoPosition:altitudeposition(0)).
    lock overshootCoords to ship:body:geopositionof(LZ:altitudeposition(0) + overshootVector).

    print "** ABORT: LZ redirected to " + round(LZ:lat,3) + ", " + round(LZ:lng,3) + " **" at (0,6).
    print "   Landing at nearest safe point." at (0,7).
}

// ── LANDING ───────────────────────────────────────────────────────────────
// DECISION: We continue aiming for the KSC launch pad (lat -0.0972, lng -74.5757).
// The boostback was getting close last run. Instead of giving up, we now
// RECORD the actual landing coordinates after every successful landing into
// a file called "lz_cal.json". On the next launch, PARAM.ks will load that
// file and offset the LZ target to compensate for the systematic drift,
// so each run self-corrects toward the pad. After 2-3 runs it should converge.
function Land {

    // ── PHASE 1: GEAR DEPLOY at 400m ─────────────────────────────────────
    until (alt:radar < 400) { wait 0. }
    gear on.
    print "Gear deployed at " + round(alt:radar) + "m.".

    // ── PHASE 2: SUICIDE BURN APPROACH ───────────────────────────────────
    // Keep tracking srfretrograde + lateral correction until close to ground.
    // RTRvector transitions to up:vector when near-stopped.
    when (ship:verticalspeed > -15) then {
        unlock RTRvector.
        lock RTRvector to up:vector.
    }

    // Engine already fired by AtmGNC. Do NOT reset throt=1 — it disrupts the burn.
    rcs on.
    lock steering to lookdirup(-up:vector, LATvector).

    local doThreeEngines is false.
    if ((landProfile > 3 or forceThree) and LandThrottle() > 1) {
        wait 1. EngSwitch(2, 1). set doThreeEngines to true.
    }

    HlatPID:reset(). HlngPID:reset().
    lock steering to lookdirup(
        (RTRvector +
         ((vcrs(RTRvector, LNGvector) * -HlatOut) +
          (vcrs(RTRvector, LATvector) * -HlngOut) *
          ((throt + max(min((250 - abs(ship:verticalspeed)) / 83.333, 2), 0)) / 3))),
        LATvector).

    if (doThreeEngines) {
        until ((landProfile > 3 or forceThree) and LandThrottle() < 0.333) { wait 0. }
        EngSwitch(1, 2).
    }

    // ── PHASE 3: THROTTLE TO LandThrottle() ──────────────────────────────
    lock throt to LandThrottle().

    // ── PHASE 4: FINAL FLARE — below 30m ──────────────────────────────────
    // Wait until nearly stopped OR we are very close to ground.
    // Do NOT switch to hover throttle — just hold suicide burn throttle
    // until contact. The old hover (1.4x) caused the booster to hold altitude
    // and then spin out. Instead: hold the computed throttle, and cut on contact.
    until (alt:radar < 8 or ship:verticalspeed > -1) { wait 0. }

    // ── PHASE 5: HARD CUT ON CONTACT ─────────────────────────────────────
    // Engine cuts as soon as we are effectively at ground level.
    // This prevents the hover loop entirely.
    set throt to 0.
    unlock throttle.
    lock throttle to 0.

    // Wait for the game to register LANDED (legs absorb impact)
    local landTimeout is time:seconds + 10.
    until (ship:status = "LANDED" or time:seconds > landTimeout) { wait 0. }

    rcs off.
    set throt to 0.
    print "LANDED at " + round(ship:geoposition:lat,4) + ", " + round(ship:geoposition:lng,4).

    // ── SELF-CALIBRATING LZ: record landing coords for next run ───────────
    // We compute how far off we landed from the target LZ and write a
    // correction file. PARAM.ks reads this on the next launch and shifts
    // the LZ target by the error, so each run converges toward the pad.
    local landedLat is ship:geoposition:lat.
    local landedLng is ship:geoposition:lng.
    local errLat is LZ:lat - landedLat.
    local errLng is LZ:lng - landedLng.

    // Load previous calibration if it exists, otherwise start fresh
    local calLex is lexicon("errLat", 0, "errLng", 0, "runs", 0).
    if exists("0:/lz_cal.json") { set calLex to readjson("0:/lz_cal.json"). }

    // Running average of landing error — 70% new measurement, 30% history.
    // This converges quickly (2-3 runs) while rejecting one-off outliers.
    local runs is calLex["runs"] + 1.
    local newErrLat is (calLex["errLat"] * 0.3) + (errLat * 0.7).
    local newErrLng is (calLex["errLng"] * 0.3) + (errLng * 0.7).

    local newCal is lexicon(
        "errLat", newErrLat,
        "errLng", newErrLng,
        "runs",   runs,
        "lastLat", landedLat,
        "lastLng", landedLng
    ).
    writejson(newCal, "0:/lz_cal.json").
    print "LZ error: dLat=" + round(errLat,4) + " dLng=" + round(errLng,4) + " (saved for next run)".
    print "After " + runs + " run(s), cumulative correction: dLat=" + round(newErrLat,4) + " dLng=" + round(newErrLng,4).
}

// ── PID SETUP ─────────────────────────────────────────────────────────────
function PIDsetup {
    global atmPID is list(45, 1.65, 3.25, tan(10)).
    global hvrPID is list(300, 75, 205, tan(15)).
    set lerpToSetpoint to 0.
    set osGain to 1.667.

    lock overshootAlt to max(0, min(0.5, (max(0, alt:radar - 6000) / 100000) ^ 0.38)).
    set overshootCoords to ship:body:geopositionof(
        LZ:altitudeposition(0) - ship:geoPosition:altitudeposition(0)).

    set AlatPID to pidloop(atmPID[0], atmPID[1], atmPID[2], -atmPID[3], atmPID[3]).
    set AlngPID to pidloop(atmPID[0], atmPID[1], atmPID[2], -atmPID[3], atmPID[3]).
    lock AlatOut to AlatPID:update(time:seconds, Impact(0, landProfile, LZ):lat).
    lock AlngOut to AlngPID:update(time:seconds, Impact(0, landProfile, LZ):lng).

    set HlatPID to pidloop(hvrPID[0], hvrPID[1], hvrPID[2], -hvrPID[3], hvrPID[3]).
    set HlatPID:setpoint to LZ:lat.
    set HlngPID to pidloop(hvrPID[0], hvrPID[1], hvrPID[2], -hvrPID[3], hvrPID[3]).
    set HlngPID:setpoint to LZ:lng.

    lock HlatOut to HlatPID:update(time:seconds,
        ((body:geoPositionof(body:position:normalized * ship:altitude):lat * 0.2) +
         (Impact(0, landProfile, LZ):lat * 0.8))).
    lock HlngOut to HlngPID:update(time:seconds,
        ((body:geoPositionof(body:position:normalized * ship:altitude):lng * 0.2) +
         (Impact(0, landProfile, LZ):lng * 0.8))).
}

// ── ENGINE SWITCH ─────────────────────────────────────────────────────────
function EngSwitch {
    parameter fromEng, toEng.
    local switchTimeout is time:seconds + 10.  // prevents infinite loop
    until (fromEng = toEng or time:seconds > switchTimeout) {
        set fromEng to fromEng + 1.
        if (fromEng > 2) { set fromEng to 0. }
        wait 0.
        toggle AG1.
    }
}
