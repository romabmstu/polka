# Contributing

Thanks for taking the time.

## Getting set up

```sh
brew install xcodegen
make project
open Polka.xcodeproj
```

`Polka.xcodeproj` is generated from `project.yml` and is not checked in. Change `project.yml`, not the project file.

To sign with your own team instead of running ad hoc, create `Config/Local.xcconfig` (it is git-ignored):

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

## Before opening a pull request

- `make test` passes. New logic goes into `Packages/PolkaKit` with tests; the app target should stay thin.
- `make format` has been run.
- User-facing strings are added to `App/Resources/Localizable.xcstrings` with an English source and a Russian translation. If you speak another language, translations are very welcome.
- Anything that runs a process, builds a script or touches the network follows the rules in [SECURITY.md](SECURITY.md).

Keep pull requests focused: one change, one reason. Describe what you tested and on which hardware (notch or external display).

## Commit messages

Imperative mood, short subject line, details in the body if needed:

```
Show meeting countdown in the closed notch

Only for events with a video link that start within 30 minutes.
```
