package asgard

// Procedurally-generated sound effects. No external audio files; each sound is
// a short sine wave with an envelope, synthesized at startup into a Sound the
// audio backend uploads once and can replay on demand.

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

AUDIO_SAMPLE_RATE :: 44100
MASTER_VOLUME     :: f32(0.6)
TAU               :: f32(6.283185307179586)

// Each attacker (player + every enemy kind) has its own strike sound, so
// "who hit whom" is audibly distinct. Add a new SoundKind here when you
// add a new enemy, then a make_sound entry in audio_init and a generator
// proc below.
SoundKind :: enum {
	Player_Strike,  // your weapon connecting (any target)
	Draugr_Strike,  // a draugr's rasping attack
	Jotunn_Strike,  // a frost giant's heavy boom
	Hound_Strike,   // a hound's sharp bite/snap
	Hel_Strike,     // Hel's slow dissonant wail
	Pickup,         // item picked up
	Use_Item,       // any pack slot consumed
	Descend,        // stepped through the World Tree
}

@(private="file")
sounds: [SoundKind]rl.Sound

audio_init :: proc() {
	rl.InitAudioDevice()
	sounds[.Player_Strike] = make_sound(0.12, gen_player_strike)
	sounds[.Draugr_Strike] = make_sound(0.25, gen_draugr_strike)
	sounds[.Jotunn_Strike] = make_sound(0.30, gen_jotunn_strike)
	sounds[.Hound_Strike]  = make_sound(0.08, gen_hound_strike)
	sounds[.Hel_Strike]    = make_sound(0.40, gen_hel_strike)
	sounds[.Pickup]        = make_sound(0.12, gen_pickup)
	sounds[.Use_Item]      = make_sound(0.20, gen_use_item)
	sounds[.Descend]       = make_sound(0.40, gen_descend)
	for k in SoundKind {
		rl.SetSoundVolume(sounds[k], MASTER_VOLUME)
	}
	music_init()
}

audio_shutdown :: proc() {
	music_shutdown()
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

// First-order high-pass state, accumulated inside gen_draugr_strike during
// its one-shot generation pass.
@(private="file") prev_draugr_noise: f32 = 0

// Hero strike — boot kick. Standard kick-drum synthesis: a sine whose
// frequency drops quickly from a "snap" frequency to a low "thump", plus
// a very short noise transient at the attack for the leather-slap.
//
// Pitch envelope: f(t) = F_BASE + F_SWING · exp(-PITCH_RATE · t)
// Phase: 2π · ∫f = 2π · (F_BASE·t + (F_SWING/PITCH_RATE)·(1 − exp(−PITCH_RATE·t)))
@(private="file")
gen_player_strike :: proc(t: f32) -> f32 {
	F_BASE     :: f32(70.0)  // settled low thump
	F_SWING    :: f32(280.0) // additional pitch at attack (so peak ≈ 350 Hz)
	PITCH_RATE :: f32(70.0)  // higher = faster pitch drop = snappier

	pitch_factor := math.exp(-t * PITCH_RATE)
	phase        := TAU * (F_BASE * t + (F_SWING / PITCH_RATE) * (1 - pitch_factor))

	amp_env := math.exp(-t * 30) // body fades over ~33 ms
	body    := math.sin(phase) * amp_env * 0.7

	// Leather-slap: tiny noise burst, gone within ~4 ms.
	noise_env := math.exp(-t * 250)
	noise     := (rand.float32() * 2 - 1) * noise_env * 0.45

	return body + noise
}

// Jotunn's boom: very low pitch-swept sine, slower decay than the kick. Same
// kick-drum synthesis recipe as the player strike but tuned for sub-bass and
// a long tail — reads as a heavy "DOOM" rather than a snap.
@(private="file")
gen_jotunn_strike :: proc(t: f32) -> f32 {
	F_BASE     :: f32(45.0)
	F_SWING    :: f32(220.0)
	PITCH_RATE :: f32(35.0)

	pitch_factor := math.exp(-t * PITCH_RATE)
	phase        := TAU * (F_BASE * t + (F_SWING / PITCH_RATE) * (1 - pitch_factor))

	amp_env := math.exp(-t * 14) // long tail
	return math.sin(phase) * amp_env * 0.9
}

// Hel's wail: long ASR envelope over a low fundamental and a tritone
// dissonance (113 Hz above 80 Hz ≈ tritone — unsettled, not musical).
// A whisper of noise layered on top. Reads as ominous, slow, distinctly
// "boss" energy — longer than any normal enemy strike.
@(private="file")
gen_hel_strike :: proc(t: f32) -> f32 {
	ATK :: f32(0.08)
	SUS :: f32(0.28)
	END :: f32(0.40)

	env: f32
	switch {
	case t < ATK: env = t / ATK
	case t < SUS: env = 1.0
	case:         env = (END - t) / (END - SUS)
	}
	if env < 0 { env = 0 }

	low       := math.sin(t *  80 * TAU) * 0.40
	dissonant := math.sin(t * 113 * TAU) * 0.25
	whisper   := (rand.float32() * 2 - 1)  * 0.08

	return env * (low + dissonant + whisper)
}

// Hound's bite: sharp noise click + brief high tone. Very short (~60ms) —
// reads as a snap or quick chomp rather than any sustained sound.
@(private="file")
gen_hound_strike :: proc(t: f32) -> f32 {
	if t > 0.06 { return 0 }

	click_env := math.exp(-t * 220)
	click     := (rand.float32() * 2 - 1) * click_env * 0.6

	ring_env  := math.exp(-t * 60)
	ring      := math.sin(t * 900 * TAU) * ring_env * 0.4

	return click + ring
}

// Draugr's hiss: sustained high-passed noise with an attack-sustain-release
// envelope. Reads as a long, dry "hsss" — held breath, not a thump.
@(private="file")
gen_draugr_strike :: proc(t: f32) -> f32 {
	ATK :: f32(0.03)
	SUS :: f32(0.18)
	END :: f32(0.25)

	env: f32
	switch {
	case t < ATK: env = t / ATK
	case t < SUS: env = 1.0
	case:         env = (END - t) / (END - SUS)
	}
	if env < 0 { env = 0 }

	n  := rand.float32() * 2 - 1
	hp := n - prev_draugr_noise
	prev_draugr_noise = n

	return env * hp * 0.30
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
