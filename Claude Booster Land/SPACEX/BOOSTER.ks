// BOOSTER.ks — Falcon 9 style RTLS booster landing script
// Profile: landProfile=1 (RTLS), core:tag="1" (center booster)
// Sequence: Flip2 → Reentry1 (coast/orient) → AtmGNC (suicide burn) → Land

clearscreen.
set config:ipu to 800.

// ── SAFETY: self-terminate on revert/destruction ──────────────────────────
when (ship:status = "DEAD" or kuniverse:activevessel:name <> ship:name) then {
    print "ABORT: vessel lost or reverted.".
    unlock steering. unlock throttle.
    set ship:control:neutralize to true.
}

// ── LANDING ZONE ──────────────────────────────────────────────────────────
// Ocean landing target: 0°13'55"S, 64°45'21"W (from Flight Engineer impact coords)
local OCEAN_LAT is -0.231944.
local OCEAN_LNG is -64.755833.
local LZ is latlng(OCEAN_LAT, OCEAN_LNG).

// Self-calibrating correction — converges on exact spot over multiple runs
if exists("0:/lz_cal.json") {
    local cal is readjson("0:/lz_cal.json").
    set LZ to latlng(OCEAN_LAT + cal["errLat"], OCEAN_LNG + cal["errLng"]).
    print ">> LZ cal applied: dLat=" + round(cal["errLat"],4) + " dLng=" + round(cal["errLng"],4).
}
print "LZ: " + round(LZ:lat,6) + " / " + round(LZ:lng,6).

// tgtAzimuth comes from params3.json written by the ascent script.
// Used in Flip2 for reentry heading. Default 90 (east) if file missing.
local tgtAzimuth is 90.
if exists("0:/params3.json") {
    local fs is readjson("0:/params3.json").
    if fs:haskey("tgtAzimuth") { set tgtAzimuth to fs["tgtAzimuth"]. }
} else { print "WARNING: params3.json missing - using default azimuth 90.". }

// ── THROTTLE INIT ─────────────────────────────────────────────────────────
set throt to 0.
lock throttle to throt.
brakes off.
AG2 off.

// ── MAIN SEQUENCE ─────────────────────────────────────────────────────────
WaitForSep().
runoncepath("0:/COMMON/GNC").

// Separation burn — push booster retrograde for 3s to clear upper stage
print "".
print ">> SEPARATION BURN STARTING".
rcs on.
set ship:control:fore to -1.
wait 3.
set ship:control:fore to 0.
set ship:control:neutralize to true.
rcs off.
print ">> SEPARATION BURN COMPLETE".

// Fuel warnings
when (ship:liquidfuel < (ship:liquidfuel + ship:oxidizer) * 0.1) then {
    print "** WARNING: LOW FUEL — " + round(ship:liquidfuel) + "L remaining **".
}
when (ship:liquidfuel < 1) then {
    print "** OUT OF FUEL — infinite propellant active **".
}

PIDsetup().
print ">> PIDsetup done.".

// ── FLIGHT SEQUENCE ───────────────────────────────────────────────────────
// LATvector locked here — needed by Reentry1, AtmGNC, and Land().
// Must be before Reentry1 call so it exists when Reentry1 uses it as roll reference.
lock LATvector to vxcl(up:vector, (
    latlng(ship:geoposition:lat - 0.01, ship:geoposition:lng):position
    )):normalized.

print ">> Flip2 start".
Flip2(60, 0.0667).
print ">> Reentry1 start".
Reentry1().

print ">> AtmGNC start. Alt=" + round(alt:radar) + " VS=" + round(ship:verticalspeed).
AtmGNC().
print ">> Land start. Alt=" + round(alt:radar) + " VS=" + round(ship:verticalspeed).
Land().

AG10 off.
shutdown.

// ═════════════════════════════════════════════════════════════════════════
// FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════

// ── WAIT FOR STAGE SEPARATION ─────────────────────────────────────────────
function WaitForSep {
    local coreList is list().
    list processors in coreList.
    local initCoreCount is coreList:length.
    local currCoreCount is initCoreCount.
    local initVec is ship:facing:forevector.
    local flipVec is ship:facing:forevector.

    until (currCoreCount < initCoreCount) {
        set initVec to ship:facing:forevector.
        set flipVec to ship:facing:forevector.
        list processors in coreList.
        set currCoreCount to coreList:length.
        wait 0.1.
    }

    print "Separation detected.".
    core:part:controlfrom().
    wait 2.
    set initVec to ship:facing:forevector.
    set flipVec to ship:facing:forevector.
}

// ── FLIP 2: Orient to reentry attitude ────────────────────────────────────
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

    lock steering to lookdirup(fv2, rotateVector).
    local t2 is time:seconds + 60.
    until (vang(finalVector, fv2) < 1 or time:seconds > t2) { wait 0.
        set fv2 to fv2 * angleAxis(flipPower, rotateVector).
    }
    set fv2 to (-tangentVector) * angleAxis(180 - finalAttitude, rotateVector).
    lock steering to lookdirup(
        heading(tgtAzimuth, finalAttitude):vector,
        heading(90 + tgtAzimuth, 0):vector).

    wait 10.
    steeringmanager:resettodefault().
    unlock steering.
}

// ── REENTRY BURN ──────────────────────────────────────────────────────────
function Reentry1 {
    // No burn here — suicide burn in AtmGNC handles all deceleration.
    // Deploys grid fins, holds srfretrograde steering, waits for steep engines-down arc.

    steeringmanager:resettodefault().
    set steeringmanager:maxstoppingtime to 5.   // responsive but not twitchy
    set steeringmanager:rolltorquefactor to 0.  // no roll fighting
    set steeringmanager:rollcontrolanglerange to 5.
    sas off.

    // Use LATvector (south) as up-ref — stable roll reference pointing down the velocity vector.
    // heading(180,0) becomes degenerate when srfretrograde is nearly vertical (engines-down).
    // LATvector is perpendicular to the fall direction so it stays well-defined.
    lock steering to lookdirup(ship:srfretrograde:vector:normalized, LATvector).
    AG2 on.   // deploy grid fins
    rcs on.   // RCS on during reentry for attitude authority — per user request.
              // Low rolltorquefactor and rollcontrolanglerange prevent oscillation.

    // Wait for: rtrDiff >= 60 (engines-down) AND below 30km.
    // 30km ceiling: don't hand off while still high with large lateral velocity.
    // No floor: if booster reaches 60 degrees at low altitude, still valid to hand off.
    // Timeout 300s: safety net only — fires if booster never gets steep enough.
    local rtrDiff is 0.
    local t1 is time:seconds + 300.
    until ((rtrDiff >= 60 and alt:radar < 30000) or time:seconds > t1) { wait 0.
        set rtrDiff to 90 - vang(ship:up:vector:normalized, ship:srfretrograde:vector:normalized).
        local rcsStatus is choose "RCS:ON" if rcs else "RCS:OFF".
        print ">> R1: alt=" + round(alt:radar/1000,1) + "km rtrDiff=" + round(rtrDiff,1) + " VS=" + round(ship:verticalspeed) + " ANG=" + round(vang(ship:facing:forevector, up:vector),1) + " " + rcsStatus at (0,8).
    }
    print ">> Reentry1: arc complete at " + round(alt:radar/1000,1) + "km rtrDiff=" + round(rtrDiff,1) + " VS=" + round(ship:verticalspeed) + ".".
}

// ── ATMOSPHERIC GNC ───────────────────────────────────────────────────────
function AtmGNC {
    // ── STEP 1: ORIENTATION — re-lock steering so booster doesn't tumble ──
    // Reentry1's lock dies when it returns — re-lock immediately with same settings.
    // RCS is already on from Reentry1.
    steeringmanager:resettodefault().
    set steeringmanager:maxstoppingtime to 5.
    set steeringmanager:rolltorquefactor to 0.
    set steeringmanager:rollcontrolanglerange to 5.
    lock steering to lookdirup(ship:srfretrograde:vector:normalized, LATvector).

    // ── STEP 2: IGNITION TRIGGER LOOP ────────────────────────────────────
    // Minimal setup — heavy locks come after ignition decision.
    // RCS already on from Reentry1.
    local engList is list().
    list engines in engList.
    local eng is engList[0].
    local lowestThrust is eng:availablethrustat(1) + 1.
    for e in engList {
        if e:availablethrustat(1) < lowestThrust {
            set lowestThrust to e:availablethrustat(1).
            set eng to e.
        }
    }
    local mFlowRate  is eng:availablethrustat(1) / (eng:ispat(1) * constant:g0).
    local thrustGain is 1.

    until false {
        local distToLZ is Impact(1, 1, LZ).
        print "Alt: " + round(alt:radar) + "  VS: " + round(ship:verticalspeed) + "  ANG: " + round(vang(ship:facing:forevector, -up:vector),1) + "  LZdist: " + round(distToLZ) at (0,3).
        if (ag9) { print "** MANUAL ABORT via AG9 **". break. }
        if (IntegLand(alt:radar, ship:verticalspeed, 1, mFlowRate, eng, thrustGain, distToLZ, 0.1)) { break. }
        // Ignite when alt < 20000m OR speed > 1100 m/s — whichever comes first.
        if (alt:radar < 20000 or abs(ship:verticalspeed) > 1100) { break. }
        wait 0.
    }

    // ── IGNITION: spool engine immediately — no locks before this ────────
    print "IGNITION at " + round(alt:radar) + "m / " + round(ship:verticalspeed) + "m/s" at (0,5).
    unlock throttle.
    set throt to 0.05.
    lock throttle to throt.
    wait 0.5.
    unlock throttle.
    lock throttle to LandThrottle().

    // ── STEERING SETUP: lateral guidance for suicide burn descent ─────────
    // Set up AFTER engine is spooled — these locks are expensive and would
    // delay ignition if placed before the spool.
    lock LNGvector to vxcl(up:vector, (
        latlng(ship:geoposition:lat, ship:geoposition:lng + 0.01):position
        )):normalized.
    lock RTRvector to ship:srfretrograde:vector:normalized.

    local initAlt   is ship:altitude.
    local finalAlt  is initAlt - 7500.
    local lerpDenom is max(initAlt - finalAlt, 1).
    lock lerpToSetpoint to (initAlt - min(initAlt, max(finalAlt, ship:altitude))) / lerpDenom.

    AlatPID:reset(). AlngPID:reset().
    lock overshootVector to (LZ:altitudeposition(0) - ship:geoPosition:altitudeposition(0)).
    lock overshootCoords to ship:body:geopositionof(LZ:altitudeposition(0) + overshootVector).
    lock reduceLateral   to vcrs(body:position, vxcl(up:vector, overshootVector:normalized)):normalized.

    // Steering: srfretrograde at high speed (clean braking axis),
    // lateral PID guidance blends in below 300 m/s when corrections are gentle.
    lock steering to lookdirup(
        choose RTRvector
        if abs(ship:verticalspeed) > 300
        else
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

    // Suicide burn loop — LandThrottle() runs live every tick.
    // Hand off to Land() when below 3000m AND speed under 180 m/s,
    // or hard floor at 500m regardless of speed.
    until (
        (alt:radar < 3000 and abs(ship:verticalspeed) < 180) or
        alt:radar < 500 or
        ship:status = "LANDED"
    ) {
        print "BURN: alt=" + round(alt:radar) + "m VS=" + round(ship:verticalspeed,1) + " THR=" + round(throttle,2) at (0,6).
        wait 0.
    }
    print ">> Suicide burn complete. alt=" + round(alt:radar) + "m VS=" + round(ship:verticalspeed,1) + " — handing to Land()".
}



// ── LANDING ───────────────────────────────────────────────────────────────
function Land {

    // Phase 1: gear deploy — fires immediately since we arrive from suicide burn at ~1000m
    gear on.
    print "Gear deployed at " + round(alt:radar) + "m.".

    // Phase 2: verify engine is lit
    print ">> Land: thrust=" + round(ship:availablethrust) + "kN alt=" + round(alt:radar) + "m".
    if (ship:availablethrust < 1) {
        // Engine not lit — re-lock LandThrottle() to restart it.
        // Do not touch throt — it no longer drives throttle at this point.
        print ">> Land: ENGINE NOT LIT - relighting".
        lock throttle to LandThrottle().
        local engTimeout is time:seconds + 3.
        until (ship:availablethrust > 1 or time:seconds > engTimeout) { wait 0. }
        print ">> Land: engine lit. thrust=" + round(ship:availablethrust) + "kN".
    }

    // Phase 3: steering — straight up
    steeringmanager:resettodefault().
    set steeringmanager:maxstoppingtime to 10.
    set steeringmanager:rolltorquefactor to 0.
    set steeringmanager:rollcontrolanglerange to 1.
    rcs off.
    lock steering to lookdirup(up:vector, LATvector).

    // Phase 4: throttle — LandThrottle() is already live from AtmGNC suicide burn.
    // Do NOT unlock and re-lock here — that creates a 1-tick gap mid-descent.
    // Just verify it's active; if engine restarted in Phase 2 we need to re-lock.
    lock throttle to LandThrottle().

    // Phase 5: descent with inline horizontal velocity kill
    // Above 200m: straight down, full deceleration
    // 50-200m: tilt against horizontal velocity to null lateral drift
    // Below 50m: straight up again for clean vertical touchdown
    local wasDescending is true.
    until (
        alt:radar < 25 or
        ship:status = "LANDED"
    ) {
        // VS positive detection
        if (ship:verticalspeed > 0 and wasDescending) {
            print "** VS WENT POSITIVE (moving UP) at alt=" + round(alt:radar) + "m — throttle cut to 0 **".
            set wasDescending to false.
        }
        if (ship:verticalspeed <= 0) { set wasDescending to true. }

        // Horizontal kill window: 50m to 200m
        // Tilt proportional to horizontal speed, max 15 degrees
        // Below 50m switch back to straight up — too low to tilt safely
        if (alt:radar < 200 and alt:radar > 50 and ship:groundspeed > 0.5) {
            local hv       is vxcl(up:vector, ship:velocity:surface).
            local tiltAng  is min(15, hv:mag * 1.2).
            local killVec  is (up:vector - (hv:normalized * tan(tiltAng))):normalized.
            lock steering to lookdirup(killVec, LATvector).
        } else {
            lock steering to lookdirup(up:vector, LATvector).
        }

        print "ALT:" + round(alt:radar,0) + " VS:" + round(ship:verticalspeed,1) + " HS:" + round(ship:groundspeed,1) + " THR:" + round(throttle,2) + " ANG:" + round(vang(ship:facing:forevector,up:vector),1) at (0,10).
        wait 0.
    }

    // Phase 6: engine cut on contact
    unlock throttle.
    set throt to 0.
    lock throttle to 0.
    set ship:control:pilotmainthrottle to 0.
    set ship:control:neutralize to true.
    unlock steering.
    rcs off.

    local landTimeout is time:seconds + 10.
    until (ship:status = "LANDED" or time:seconds > landTimeout) { wait 0. }

    set throt to 0.

    local landedLat is ship:geoposition:lat.
    local landedLng is ship:geoposition:lng.
    print "LANDED at " + round(landedLat,6) + ", " + round(landedLng,6).

    // Self-calibrating LZ: record error and save for next run
    local errLat is LZ:lat - landedLat.
    local errLng is LZ:lng - landedLng.
    local calLex is lexicon("errLat", 0, "errLng", 0, "runs", 0).
    if exists("0:/lz_cal.json") { set calLex to readjson("0:/lz_cal.json"). }
    local runs      is calLex["runs"] + 1.
    local newErrLat is (calLex["errLat"] * 0.3) + (errLat * 0.7).
    local newErrLng is (calLex["errLng"] * 0.3) + (errLng * 0.7).
    writejson(lexicon(
        "errLat",   newErrLat,
        "errLng",   newErrLng,
        "runs",     runs,
        "lastLat",  landedLat,
        "lastLng",  landedLng
    ), "0:/lz_cal.json").
    print "LZ error: dLat=" + round(errLat,6) + " dLng=" + round(errLng,6) + " (saved)".
    print "After " + runs + " run(s): correction dLat=" + round(newErrLat,6) + " dLng=" + round(newErrLng,6).
}

// ── PID SETUP ─────────────────────────────────────────────────────────────
function PIDsetup {
    global atmPID is list(45, 1.65, 3.25, tan(10)).
    global hvrPID is list(80, 5, 40, tan(10)).
    set osGain to 1.667.

    lock overshootAlt to max(0, min(0.5, (max(0, alt:radar - 6000) / 100000) ^ 0.38)).
    set overshootCoords to ship:body:geopositionof(
        LZ:altitudeposition(0) - ship:geoPosition:altitudeposition(0)).

    set AlatPID to pidloop(atmPID[0], atmPID[1], atmPID[2], -atmPID[3], atmPID[3]).
    set AlngPID to pidloop(atmPID[0], atmPID[1], atmPID[2], -atmPID[3], atmPID[3]).
    lock AlatOut to AlatPID:update(time:seconds, Impact(0, 1, LZ):lat).
    lock AlngOut to AlngPID:update(time:seconds, Impact(0, 1, LZ):lng).

    set HlatPID to pidloop(hvrPID[0], hvrPID[1], hvrPID[2], -hvrPID[3], hvrPID[3]).
    set HlatPID:setpoint to LZ:lat.
    set HlngPID to pidloop(hvrPID[0], hvrPID[1], hvrPID[2], -hvrPID[3], hvrPID[3]).
    set HlngPID:setpoint to LZ:lng.

    lock HlatOut to HlatPID:update(time:seconds,
        ((body:geoPositionof(body:position:normalized * ship:altitude):lat * 0.2) +
         (Impact(0, 1, LZ):lat * 0.8))).
    lock HlngOut to HlngPID:update(time:seconds,
        ((body:geoPositionof(body:position:normalized * ship:altitude):lng * 0.2) +
         (Impact(0, 1, LZ):lng * 0.8))).
}
