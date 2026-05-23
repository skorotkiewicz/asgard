package asgard

// Procedurally-generated sound effects. No external audio files; each sound is
// a short sine wave with an envelope, synthesized at startup into a Sound the
// audio backend uploads once and can replay on demand.

import "core:math"
import rl "vendor:raylib"

AUDIO_SAMPLE_RATE :: 44100
MASTER_VOLUME     :: f32(0.6)
TAU               :: f32(6.283185307179586)

SoundKind :: enum {
	Enemy_Hit,   // you hit a foe
	Player_Hit,  // you got hit
	Pickup,      // item picked up
	Use_Item,    // any pack slot consumed
	Descend,     // stepped through the World Tree
}

@(private="file")
sounds: [SoundKind]rl.Sound

audio_init :: proc() {
	rl.InitAudioDevice()
	sounds[.Enemy_Hit]  = make_sound(0.10, gen_enemy_hit)
	sounds[.Player_Hit] = make_sound(0.15, gen_player_hit)
	sounds[.Pickup]     = make_sound(0.12, gen_pickup)
	sounds[.Use_Item]   = make_sound(0.20, gen_use_item)
	sounds[.Descend]    = make_sound(0.40, gen_descend)
	for k in SoundKind {
		rl.SetSoundVolume(sounds[k], MASTER_VOLUME)
	}
}

audio_shutdown :: proc() {
	for k in SoundKind {
		rl.UnloadSound(sounds[k])
	}
	rl.CloseAudioDevice()
}

play_sound :: proc(kind: SoundKind) {
	rl.PlaySound(sounds[kind])
}

// ---- synthesis -------------------------------------------------------------

// Build a Sound by sampling `gen(t)` for `duration_sec` at AUDIO_SAMPLE_RATE.
// `gen` returns a sample in [-1, 1] (will be clamped).
@(private="file")
make_sound :: proc(duration_sec: f32, gen: proc(t: f32) -> f32) -> rl.Sound {
	n := int(AUDIO_SAMPLE_RATE * duration_sec)
	data := make([]i16, n)
	defer delete(data) // LoadSoundFromWave copies into the audio backend

	for i in 0 ..< n {
		t := f32(i) / AUDIO_SAMPLE_RATE
		s := gen(t)
		if s >  1.0 { s =  1.0 }
		if s < -1.0 { s = -1.0 }
		data[i] = i16(s * 32760)
	}

	wave := rl.Wave{
		frameCount = u32(n),
		sampleRate = AUDIO_SAMPLE_RATE,
		sampleSize = 16,
		channels   = 1,
		data       = raw_data(data),
	}
	return rl.LoadSoundFromWave(wave)
}

// ---- generators ------------------------------------------------------------
// Each returns a single sample at time `t` (seconds since the sound began).

@(private="file")
gen_enemy_hit :: proc(t: f32) -> f32 {
	env := math.exp(-t * 30)
	return env * 0.7 * math.sin(t * 220 * TAU)
}

@(private="file")
gen_player_hit :: proc(t: f32) -> f32 {
	env := math.exp(-t * 18)
	return env * 0.85 * math.sin(t * 90 * TAU)
}

@(private="file")
gen_pickup :: proc(t: f32) -> f32 {
	env := math.exp(-t * 22)
	return env * 0.5 * math.sin(t * 800 * TAU)
}

@(private="file")
gen_use_item :: proc(t: f32) -> f32 {
	env := math.exp(-t * 12)
	return env * 0.55 * math.sin(t * 500 * TAU)
}

@(private="file")
gen_descend :: proc(t: f32) -> f32 {
	// AR-style envelope: quick fade in, sustain, soft fade out.
	env: f32 = 1.0
	if t < 0.05 { env = t / 0.05 }
	if t > 0.30 { env = (0.40 - t) / 0.10 }
	if env < 0  { env = 0 }
	return env * 0.5 * math.sin(t * 180 * TAU)
}
