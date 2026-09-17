# pi-bend

Native Bend port of pi, based on `earendil-works/pi` revision `46c9de402` (0.85.1). Work in progress; this is not yet a feature-complete replacement.

Application logic lives in Bend. Native C effects provide operating-system and library interfaces. JavaScript/TypeScript extension compatibility is intentionally excluded; extensions will use Bend.

See [docs/parity.md](docs/parity.md) for the implementation and validation status. Credentials remain in the existing private `~/.pi/agent/auth.json`; never copy credentials into this repository.
