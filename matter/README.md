# Matter SDK for Android

ZT Home controls Matter devices with the open Matter SDK
([project-chip/connectedhomeip](https://github.com/project-chip/connectedhomeip),
Apache 2.0), not with Google Play services, so it works on phones without
them (GrapheneOS) and keeps its own Matter fabric.

The SDK has no published Android package, so this repository builds it:

- `sdk.env` names the SDK release.
- `.github/workflows/matter-sdk.yml` builds the SDK's Android controller
  libraries (the `.jar` files and `libCHIPController.so`) for that release,
  in the SDK project's own build image, and publishes them as the GitHub
  release `matter-sdk-<tag>` of this repository.

The app's Android build takes the libraries from that release.

To move to a newer SDK: change the tag in `sdk.env` in a pull request. The
pull request builds the libraries (about an hour), so a release that
doesn't build is caught before it merges; merging into `Dev` publishes
them.
