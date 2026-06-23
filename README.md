# dwanim

> A lightweight, skinnable native macOS music player for your local music collection.

## The name

**dwanim** takes its name from **Dwennimmen** ("ram's horns"), an Adinkra symbol
from the Akan culture of West Africa. The symbol represents the coexistence of
**humility and strength** — power held together with restraint. This Adinkra
heritage is the single, canonical origin of the project's name, and the guiding
theme for its identity, iconography, and default appearance.

## What it is

dwanim is a native macOS music player for people who keep and play their own
local music files. It is built natively for Apple Silicon and focuses on doing
one thing with care: letting you customize how the player looks.

A core feature is skinning: dwanim supports classic `.wsz` skin files, so you
can load your own skin files and shape the interface to your taste. dwanim does
not bundle any third-party skins — it ships with its own original,
Adinkra-themed default appearance, and a classic skin only appears when you
choose to load your own `.wsz` file.

### Features (planned)

- Native macOS app, Apple Silicon native.
- Local audio playback: MP3, AAC, ALAC, FLAC, WAV, AIFF (via AVFoundation).
- Transport controls: play, pause, seek, previous / next, volume.
- Loads user-provided classic `.wsz` skin files (file picker + drag and drop).
- Spectrum visualizer.
- A simple playlist.

> **Status:** early scaffolding. Implementation is in progress; no application
> code ships yet.

## Skins

dwanim loads `.wsz` skin files that *you* provide. It does not host, bundle, or
redistribute skins of any kind. Publicly archived classic skins can be found
through open archives such as the [Internet Archive](https://archive.org/).

## Clean-room & licensing

dwanim is a clean-room, independent implementation. It does not use, reference,
or port any proprietary source code. Reading the `.wsz` file format — a file
format, not a copyrightable work — is the extent of the compatibility goal.

The project is open source under the [MIT License](LICENSE). For third-party
references and the attributions their licenses require, see
[THIRD_PARTY.md](THIRD_PARTY.md).

## License

MIT © dwanim-app. See [LICENSE](LICENSE).
