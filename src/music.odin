package asgard

// Background music: per-realm generative ambient — a 30-second loop containing
// a handful of randomly-scheduled note events drawn from the realm's tonal
// palette. Each note has a bell envelope (fade in / peak / fade out) so
// boundaries are silent and the loop seam is naturally seamless. Realms feel
// distinct via their palette; the sparseness avoids the "constant mmmmm" of a
// sustained drone.

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

MUSIC_VOLUME    :: f32(0.30)
LOOP_DURATION   :: f32(30.0)  // seconds per loop
NOTES_PER_LOOP  :: 7          // average note count per loop (random timing)
NOTE_MIN_DUR    :: f32(1.5)
NOTE_MAX_DUR    :: f32(3.5)
NOTE_GUARD_END  :: f32(0.5)   // keep last 0.5s clear so notes finish before loop seam
NOTE_AMP_MIN    :: f32(0.15)
NOTE_AMP_MAX    :: f32(0.25)

NoteEvent :: struct {
	start:    f32, // seconds from loop start
	freq:     f32, // Hz
	duration: f32, // seconds
	amp:      f32, // peak amplitude
}

@(private="file") realm_musics:      [Realm]rl.Music
@(private="file") realm_wav_bufs:    [Realm][]byte // kept alive: raylib streams from these
@(private="file") current_realm:     Realm
@(private="file") current_realm_set: bool

// Session-only music toggle (defaults to on). Survives New Game so the
// user's preference isn't wiped on restart.
@(private="file") music_enabled:     bool = true

is_music_enabled :: proc() -> bool { return music_enabled }

set_music_enabled :: proc(on: bool) {
	if music_enabled == on { return }
	music_enabled = on
	if !current_realm_set { return }
	if on {
		rl.PlayMusicStream(realm_musics[current_realm])
	} else {
		rl.StopMusicStream(realm_musics[current_realm])
	}
}

music_init :: proc() {
	for r in Realm {
		realm_wav_bufs[r]     = build_realm_wav(r)
		realm_musics[r]       = rl.LoadMusicStreamFromMemory(
			".wav",
			raw_data(realm_wav_bufs[r]),
			i32(len(realm_wav_bufs[r])),
		)
		realm_musics[r].looping = true
		rl.SetMusicVolume(realm_musics[r], MUSIC_VOLUME)
	}
}

music_shutdown :: proc() {
	for r in Realm {
		rl.UnloadMusicStream(realm_musics[r])
		delete(realm_wav_bufs[r])
	}
	current_realm_set = false
}

// Switch to the music for `r`. No-op if already playing that realm's track.
// Skips PlayMusicStream when the user has muted music in settings.
play_realm_music :: proc(r: Realm) {
	if current_realm_set && current_realm == r { return }
	if current_realm_set {
		rl.StopMusicStream(realm_musics[current_realm])
	}
	current_realm     = r
	current_realm_set = true
	if music_enabled {
		rl.PlayMusicStream(realm_musics[r])
	}
}

// Must be called every frame from the main loop — raylib's music stream
// fills its internal buffer on demand and goes silent without this tick.
tick_music :: proc() {
	if current_realm_set && music_enabled {
		rl.UpdateMusicStream(realm_musics[current_realm])
	}
}

// ---- synthesis -------------------------------------------------------------

@(private="file")
build_realm_wav :: proc(r: Realm) -> []byte {
	events := build_realm_events(r)
	defer delete(events)

	n := int(AUDIO_SAMPLE_RATE * LOOP_DURATION)
	samples := make([]i16, n)
	defer delete(samples)

	inv_sr := f32(1.0) / AUDIO_SAMPLE_RATE

	for i in 0 ..< n {
		t := f32(i) * inv_sr

		// Sum every currently-active note. Most events are inactive at any t,
		// so the inner cost is dominated by the range check.
		sample: f32 = 0
		for e in events {
			local_t := t - e.start
			if local_t < 0 || local_t > e.duration { continue }

			// Bell envelope: sin(π · phase) — 0 → 1 → 0 across the note,
			// smooth at both edges so no click on entry or exit.
			phase := local_t / e.duration
			env   := math.sin(phase * (TAU * 0.5))

			// Sine restarts from phase 0 for each note (local_t starts at 0),
			// so amplitude is 0 at the very first sample — no click.
			sine  := math.sin(local_t * e.freq * TAU)

			sample += env * sine * e.amp
		}

		if sample >  1.0 { sample =  1.0 }
		if sample < -1.0 { sample = -1.0 }
		samples[i] = i16(sample * 32760)
	}

	return build_wav(samples)
}

// Schedules NOTES_PER_LOOP notes at random times within the loop, picking
// frequencies from the realm's tonal palette. Uses a stable per-realm seed
// so each realm's music is reproducible across runs and distinct from others.
@(private="file")
build_realm_events :: proc(r: Realm) -> []NoteEvent {
	// 4 tones per realm gives the randomizer enough variety while keeping
	// each realm's tonal character recognizable. All Hz are integer for
	// pitch stability and editorial simplicity (no microtonal drift).
	midgard      := [?]f32{196, 294, 392, 587}   // G3, D4, G4, D5 — fifth + octave
	asgard       := [?]f32{220, 277, 330, 440}   // A major triad + octave
	jotunheim    := [?]f32{196, 247, 262, 392}   // G + B + C cluster + octave
	niflheim     := [?]f32{220, 294, 392, 494}   // A, D, G, B — open fourths
	muspelheim   := [?]f32{196, 277, 392, 554}   // tritone (G/C#) across two octaves
	alfheim      := [?]f32{330, 494, 659, 988}   // E + B in upper octaves — shimmer
	svartalfheim := [?]f32{165, 247, 330, 494}   // E + B over two octaves — somber
	vanaheim     := [?]f32{220, 330, 440, 587}   // A, E, A, D — wide fifth
	helheim      := [?]f32{147, 220, 233, 311}   // D + A + A# + D# — dark cluster

	tones: []f32
	switch r {
	case .Midgard:      tones = midgard[:]
	case .Asgard:       tones = asgard[:]
	case .Jotunheim:    tones = jotunheim[:]
	case .Niflheim:     tones = niflheim[:]
	case .Muspelheim:   tones = muspelheim[:]
	case .Alfheim:      tones = alfheim[:]
	case .Svartalfheim: tones = svartalfheim[:]
	case .Vanaheim:     tones = vanaheim[:]
	case .Helheim:      tones = helheim[:]
	}

	// Stable per-realm seed: same music for the same realm every launch,
	// distinct across realms. (Music init runs before any game-state rand,
	// so this doesn't affect map-gen determinism.)
	rand.reset(u64(int(r) + 1) * 1000003)

	max_start := LOOP_DURATION - NOTE_MAX_DUR - NOTE_GUARD_END
	events := make([dynamic]NoteEvent, 0, NOTES_PER_LOOP)
	for _ in 0 ..< NOTES_PER_LOOP {
		start    := rand.float32() * max_start
		duration := NOTE_MIN_DUR + rand.float32() * (NOTE_MAX_DUR - NOTE_MIN_DUR)
		freq     := tones[rand.int_max(len(tones))]
		amp      := NOTE_AMP_MIN + rand.float32() * (NOTE_AMP_MAX - NOTE_AMP_MIN)
		append(&events, NoteEvent{start = start, freq = freq, duration = duration, amp = amp})
	}
	return events[:]
}

// ---- WAV container ---------------------------------------------------------
// Builds a minimal canonical RIFF/WAVE/fmt/data file for 16-bit mono PCM at
// AUDIO_SAMPLE_RATE. raylib's drwav parser reads from the returned byte buffer
// for the lifetime of the music stream, so the caller must keep it alive.

@(private="file")
build_wav :: proc(samples: []i16) -> []byte {
	data_bytes := u32(len(samples) * 2)
	buf := make([]byte, 44 + int(data_bytes))

	write_str(buf,  0, "RIFF")
	write_u32_le(buf,  4, 36 + data_bytes)
	write_str(buf,  8, "WAVE")

	write_str(buf, 12, "fmt ")
	write_u32_le(buf, 16, 16)                          // PCM fmt chunk size
	write_u16_le(buf, 20, 1)                           // PCM format
	write_u16_le(buf, 22, 1)                           // mono
	write_u32_le(buf, 24, u32(AUDIO_SAMPLE_RATE))
	write_u32_le(buf, 28, u32(AUDIO_SAMPLE_RATE) * 2)  // byte rate (mono × 2 bytes)
	write_u16_le(buf, 32, 2)                           // block align
	write_u16_le(buf, 34, 16)                          // bits per sample

	write_str(buf, 36, "data")
	write_u32_le(buf, 40, data_bytes)

	for s, i in samples {
		u := u16(s)
		buf[44 + i*2]     = byte(u & 0xFF)
		buf[44 + i*2 + 1] = byte((u >> 8) & 0xFF)
	}

	return buf
}

@(private="file")
write_str :: proc(buf: []byte, offset: int, s: string) {
	for i in 0 ..< len(s) {
		buf[offset + i] = s[i]
	}
}

@(private="file")
write_u32_le :: proc(buf: []byte, offset: int, v: u32) {
	buf[offset+0] = byte(v       & 0xFF)
	buf[offset+1] = byte((v >>  8) & 0xFF)
	buf[offset+2] = byte((v >> 16) & 0xFF)
	buf[offset+3] = byte((v >> 24) & 0xFF)
}

@(private="file")
write_u16_le :: proc(buf: []byte, offset: int, v: u16) {
	buf[offset+0] = byte(v       & 0xFF)
	buf[offset+1] = byte((v >> 8) & 0xFF)
}
