# dwanim it

> A lightweight, skinnable native macOS music player for your local music collection.

## The name

**dwanim it** takes its name from **Dwennimmen** ("ram's horns"), an Adinkra symbol
from the Akan culture of West Africa. The symbol represents the coexistence of
**humility and strength** — power held together with restraint. This Adinkra
heritage is the single, canonical origin of the project's name, and the guiding
theme for its identity, iconography, and default appearance.

## What it is

dwanim it is a native macOS music player for people who keep and play their own
local music files. It is a universal build (Apple Silicon and Intel) and focuses
on doing one thing with care: letting you customize how the player looks.

A core feature is skinning: dwanim it supports classic `.wsz` skin files, so you
can load your own skin files and shape the interface to your taste. dwanim it does
not bundle any third-party skins — it ships with its own original,
Adinkra-themed default appearance, and a classic skin only appears when you
choose to load your own `.wsz` file.

### Features

- Native macOS app (macOS 14+), universal binary, no third-party dependencies.
- Local audio playback: MP3, AAC (`.m4a`/`.aac`), ALAC, FLAC (native `.flac` only — Ogg-wrapped FLAC does not play), WAV, AIFF, CAF (via AVFoundation).
- Transport controls: play, pause, stop, seek, previous / next, volume, balance,
  shuffle and repeat.
- A playlist with add / remove / reorder / sort, drag and drop, and `.m3u`
  open and save.
- A 10-band equalizer with real DSP and built-in presets.
- Spectrum visualizer.
- Two faces for the player: the built-in default view, and classic `.wsz` skins
  loaded from your own files (file picker + drag and drop).
- Colour themes for the default view — three built in, plus loadable
  `.dwtheme` / `.json` theme files.
- Runs in the macOS App Sandbox with no network access at all.

> **Status:** feature-complete and building. The app runs, and the `SkinKit`
> package it is built on passes its full test suite. Store submission is in
> preparation; no release date is announced.

## Skins

dwanim it loads `.wsz` skin files that *you* provide. It does not host, bundle, or
redistribute skins of any kind. Publicly archived classic skins can be found
through open archives such as the [Internet Archive](https://archive.org/).

## Independent implementation & licensing

dwanim it is an independent implementation. The `.wsz` parsing and sprite-coordinate
code was authored from the public format specification and empirically corrected by
measuring a local corpus of real skins. No proprietary source code is included or
ported. Reading the `.wsz` file format — a file format, not a copyrightable work —
is the extent of the compatibility goal.

The project is open source under the [MIT License](LICENSE). For third-party
references and the attributions their licenses require, see
[THIRD_PARTY.md](THIRD_PARTY.md).

## License

MIT © dwanim-app. See [LICENSE](LICENSE).
