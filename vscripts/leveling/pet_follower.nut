// TF2 Leveling System - Pet Follower VScript v1.5.0
// base_boss entity with MOVETYPE_NOCLIP for universal map support.
// XY: SetAbsVelocity drives smooth horizontal movement.
// Z:  SetAbsOrigin pins pet to owner's Z + hover/jump offset each tick.
// Sounds: EmitSoundEx with configurable pitch for idle and jump sounds.
// Works on all maps including navmesh-less dodgeball maps.
//
// Install: tf/scripts/vscripts/leveling/pet_follower.nut

FOLLOW_DIST <- 80.0;
DEADZONE <- 20.0;
SPEED_SCALE <- 1.2;
TELEPORT_DIST <- 1024.0;
TURN_RATE <- 6.0;

// Jump arc
JUMP_VEL <- 150.0;
JUMP_GRAVITY <- 400.0;

// Animation
seq_idle <- -1;
seq_walk <- -1;
seq_jump <- -1;
cur_anim_seq <- -1;

// Height offset for hover pets
if (!("height_offset" in this))
    height_offset <- 0.0;

// Sound system — SM sets these before loading this file
if (!("sound_idle_list" in this))
    sound_idle_list <- [];
if (!("sound_jump" in this))
    sound_jump <- "";
if (!("sound_walk" in this))
    sound_walk <- "";
if (!("sound_pitch" in this))
    sound_pitch <- 100;
if (!("sound_volume" in this))
    sound_volume <- 0.5;
if (!("pet_debug" in this))
    pet_debug <- 0;

// Sound timing
sound_idle_next <- 0.0;
sound_walk_next <- 0.0;
SOUND_IDLE_MIN <- 5.0;
SOUND_IDLE_MAX <- 15.0;
SOUND_WALK_INTERVAL <- 0.6;  // footstep every ~0.6s while moving
played_jump_sound <- false;

// Jump state
was_owner_on_ground <- true;
jump_z_vel <- 0.0;
is_jumping <- false;
jump_height <- 0.0;

// Mood
pet_mood <- 0;
mood_next_change <- 0.0;
mood_particle <- null;
mood_particles <- [
    "superrare_beams1_newstyle",
    "",
    "superrare_flies",
    "superrare_stormcloud"
];

function PetInit()
{
    // NOCLIP required — NextBot locomotion needs navmesh which dodgeball
    // maps don't have. With NOCLIP, SetAbsVelocity drives XY movement
    // and we handle Z ourselves via SetAbsOrigin.
    self.SetMoveType(8, 0);  // MOVETYPE_NOCLIP

    // Enable all bodygroups (e.g. manhack blades, scanner lens)
    // Models without extra bodygroups are unaffected.
    for (local bg = 0; bg < 8; bg++)
    {
        try { self.SetBodygroup(bg, 1); }
        catch(e) { break; }
    }

    seq_idle = self.LookupSequence("idle");
    if (seq_idle == -1) seq_idle = self.LookupSequence("Idle01");
    if (seq_idle == -1) seq_idle = self.LookupSequence("Idle");

    seq_walk = self.LookupSequence("walk");
    if (seq_walk == -1) seq_walk = self.LookupSequence("run1");
    if (seq_walk == -1) seq_walk = self.LookupSequence("Run1");
    if (seq_walk == -1) seq_walk = self.LookupSequence("Run_All");
    if (seq_walk == -1) seq_walk = self.LookupSequence("Walk");

    seq_jump = self.LookupSequence("jump");
    if (seq_jump == -1) seq_jump = self.LookupSequence("JumpAttack_Broadcast");
    if (seq_jump == -1) seq_jump = self.LookupSequence("jumpattack_broadcast");
    if (seq_jump == -1) seq_jump = self.LookupSequence("JumpAttack");
    if (seq_jump == -1) seq_jump = self.LookupSequence("jumpattack");
    if (seq_jump == -1) seq_jump = self.LookupSequence("attack");
    if (seq_jump == -1) seq_jump = self.LookupSequence("Attack");
    if (seq_jump == -1) seq_jump = self.LookupSequence("Spitattack");
    if (seq_jump == -1) seq_jump = self.LookupSequence("LeapStrike");
    if (seq_jump == -1) seq_jump = self.LookupSequence("Jump_Start");
    if (seq_jump == -1) seq_jump = self.LookupSequence("Hop");
    if (seq_jump == -1) seq_jump = self.LookupSequence("hop");

    if (seq_idle >= 0)
    {
        self.SetSequence(seq_idle);
        cur_anim_seq = seq_idle;
    }

    // === DEBUG: controlled by sm_leveling_pet_debug cvar ===
    if (pet_debug)
    {
        local mdl = self.GetModelName();
        printl("[PET] Model: " + mdl);
        printl("[PET] Sequences: idle=" + seq_idle + " walk=" + seq_walk + " jump=" + seq_jump);

        for (local i = 0; i <= 80; i++)
        {
            try {
                local name = self.GetSequenceName(i);
                if (name != null && name != "" && name != "Unknown")
                    printl("[PET]   seq[" + i + "] = " + name);
                else
                    break;
            } catch(e) {
                break;
            }
        }

        printl("[PET] Sounds: idle_count=" + sound_idle_list.len() + " pitch=" + sound_pitch + " vol=" + sound_volume);
        foreach (idx, snd in sound_idle_list)
            printl("[PET]   idle[" + idx + "] = " + snd);
        printl("[PET]   jump = " + sound_jump);
        printl("[PET]   walk = " + sound_walk);
        printl("[PET] === END DEBUG ===");
    }

    mood_next_change = Time() + RandomFloat(30.0, 60.0);
    sound_idle_next = Time() + RandomFloat(SOUND_IDLE_MIN, SOUND_IDLE_MAX);
    AddThinkToEnt(self, "PetThink");
}

function PlaySequence(seq)
{
    if (seq < 0 || seq == cur_anim_seq) return;
    self.SetSequence(seq);
    self.SetCycle(0.0);
    cur_anim_seq = seq;
}

function PlayPetSound(sound_path, vol)
{
    if (sound_path == "" || sound_path == null) return;
    EmitSoundEx({
        sound_name = sound_path,
        entity = self,
        volume = vol,
        sound_level = 72,
        pitch = sound_pitch,
        filter_type = Constants.EScriptRecipientFilter.RECIPIENT_FILTER_DEFAULT
    });
}

function PlayIdleSound()
{
    if (sound_idle_list.len() == 0) return;
    local idx = RandomInt(0, sound_idle_list.len() - 1);
    PlayPetSound(sound_idle_list[idx], sound_volume);
}

function PlayJumpSound()
{
    if (sound_jump == "" || sound_jump == null) return;
    PlayPetSound(sound_jump, sound_volume);
}

function PlayWalkSound()
{
    if (sound_walk == "" || sound_walk == null) return;
    PlayPetSound(sound_walk, sound_volume * 0.5);
}

function StopPetSound(sound_path)
{
    if (sound_path == "" || sound_path == null) return;
    EmitSoundEx({
        sound_name = sound_path,
        entity = self,
        flags = 4,  // SND_STOP
        filter_type = Constants.EScriptRecipientFilter.RECIPIENT_FILTER_DEFAULT
    });
}

function StopAllPetSounds()
{
    // Stop all idle sounds
    foreach (snd in sound_idle_list)
        StopPetSound(snd);
    // Stop jump and walk sounds
    StopPetSound(sound_jump);
    StopPetSound(sound_walk);
}

function SetMoodParticle(particle_name)
{
    if (mood_particle != null && mood_particle.IsValid())
    {
        mood_particle.Destroy();
        mood_particle = null;
    }
    if (particle_name == "" || particle_name == null) return;
    mood_particle = SpawnEntityFromTable("info_particle_system", {
        origin = self.GetOrigin(),
        effect_name = particle_name
    });
    if (mood_particle != null && mood_particle.IsValid())
    {
        EntFireByHandle(mood_particle, "SetParent", "!activator", 0.0, self, null);
        EntFireByHandle(mood_particle, "Start", "", 0.01, null, null);
    }
}

function UpdateMood()
{
    if (Time() < mood_next_change) return;
    local roll = RandomInt(0, 100);
    local new_mood;
    if (roll < 50) new_mood = 0;
    else if (roll < 75) new_mood = 1;
    else if (roll < 90) new_mood = 2;
    else new_mood = 3;
    if (new_mood != pet_mood)
    {
        pet_mood = new_mood;
        SetMoodParticle(mood_particles[pet_mood]);
    }
    mood_next_change = Time() + RandomFloat(30.0, 90.0);
}

function PetThink()
{
    local owner = self.GetOwner();
    if (owner == null || !owner.IsValid())
        return -1;

    if (NetProps.GetPropInt(owner, "m_lifeState") != 0)
    {
        self.SetAbsVelocity(Vector(0, 0, 0));
        // Stop all sounds on the pet entity when owner is dead
        StopAllPetSounds();
        PlaySequence(seq_idle);
        self.StudioFrameAdvance();
        return -1;
    }

    UpdateMood();

    local pet_pos = self.GetOrigin();
    local owner_pos = owner.GetOrigin();
    local dt = FrameTime();

    local dx = owner_pos.x - pet_pos.x;
    local dy = owner_pos.y - pet_pos.y;
    local dist_2d = sqrt(dx * dx + dy * dy);

    // Emergency teleport
    if (dist_2d > TELEPORT_DIST)
    {
        local rx = RandomFloat(-80.0, 80.0);
        local ry = RandomFloat(-80.0, 80.0);
        self.SetAbsOrigin(Vector(owner_pos.x + rx, owner_pos.y + ry, owner_pos.z));
        is_jumping = false;
        jump_height = 0.0;
        self.StudioFrameAdvance();
        return -1;
    }

    // XY movement — SetAbsVelocity drives NextBot locomotion
    local owner_speed = NetProps.GetPropFloat(owner, "m_flMaxspeed");
    if (owner_speed <= 0.0) owner_speed = 300.0;
    local max_pet_speed = owner_speed * SPEED_SCALE;

    local vx = 0.0;
    local vy = 0.0;
    local dist_from_ideal = dist_2d - FOLLOW_DIST;

    if (dist_from_ideal > DEADZONE)
    {
        local urgency = dist_from_ideal / 200.0;
        if (urgency > 1.0) urgency = 1.0;
        local speed = max_pet_speed * urgency;
        local inv_dist = 1.0 / dist_2d;
        vx = dx * inv_dist * speed;
        vy = dy * inv_dist * speed;
    }
    else if (dist_from_ideal < -DEADZONE)
    {
        local speed = max_pet_speed * 0.3;
        local inv_dist = 1.0 / dist_2d;
        vx = -dx * inv_dist * speed;
        vy = -dy * inv_dist * speed;
    }

    self.SetAbsVelocity(Vector(vx, vy, 0));

    // Jump detection
    local owner_flags = NetProps.GetPropInt(owner, "m_fFlags");
    local owner_on_ground = (owner_flags & 1) != 0;

    if (!owner_on_ground && was_owner_on_ground && !is_jumping)
    {
        is_jumping = true;
        jump_z_vel = JUMP_VEL;
        jump_height = 0.0;
        played_jump_sound = false;
    }
    was_owner_on_ground = owner_on_ground;

    // Play jump sound once at start of jump
    if (is_jumping && !played_jump_sound)
    {
        PlayJumpSound();
        played_jump_sound = true;
    }

    // Jump arc simulation
    if (is_jumping)
    {
        jump_z_vel -= JUMP_GRAVITY * dt;
        jump_height += jump_z_vel * dt;

        if (jump_height <= 0.0 && jump_z_vel < 0.0)
        {
            jump_height = 0.0;
            is_jumping = false;
            jump_z_vel = 0.0;
        }
    }

    // Z positioning:
    // With NOCLIP, there's no ground-snapping. We must always set Z.
    // Use owner's Z as ground reference, add hover + jump offset.
    local cur = self.GetOrigin();
    local z_offset = height_offset + jump_height;
    local target_z = owner_pos.z + z_offset;
    self.SetAbsOrigin(Vector(cur.x, cur.y, target_z));

    // Idle sounds on timer
    if (Time() >= sound_idle_next)
    {
        PlayIdleSound();
        sound_idle_next = Time() + RandomFloat(SOUND_IDLE_MIN, SOUND_IDLE_MAX);
    }

    // Animation
    local horiz_speed = sqrt(vx * vx + vy * vy);

    // Walk sounds on interval while pet is moving
    if (horiz_speed > 20.0 && !is_jumping && Time() >= sound_walk_next)
    {
        PlayWalkSound();
        sound_walk_next = Time() + SOUND_WALK_INTERVAL;
    }

    if (is_jumping && seq_jump >= 0)
        PlaySequence(seq_jump);
    else if (horiz_speed > 20.0 && seq_walk >= 0)
        PlaySequence(seq_walk);
    else if (seq_idle >= 0)
        PlaySequence(seq_idle);

    // Smooth yaw
    if (dist_2d > 32.0)
    {
        local target_yaw = atan2(dy, dx) * 180.0 / PI;
        local cur_ang = self.GetAbsAngles();
        local diff = target_yaw - cur_ang.y;
        while (diff > 180.0) diff -= 360.0;
        while (diff < -180.0) diff += 360.0;
        local step = diff * TURN_RATE * dt;
        if (fabs(diff) < 1.0)
            cur_ang.y = target_yaw;
        else
            cur_ang.y = cur_ang.y + step;
        self.SetAbsAngles(cur_ang);
    }

    self.StudioFrameAdvance();
    self.DispatchAnimEvents(self);
    if (self.GetCycle() > 0.99)
        self.SetCycle(0.0);

    return -1;
}

PetInit();
