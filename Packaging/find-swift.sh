# Resolves the Swift this project has to be built with, rather than taking
# whatever is first on PATH.
#
# Source this, then:
#
#     SWIFT="$(find_swift)"
#
# Under `set -e` a failure here stops the caller, which is the point: there is
# no sensible fallback.
#
# Why this exists. `swift` on PATH is regularly not Xcode's — swiftly,
# swiftenv, asdf and the swift.org package installer all put their own ahead
# of it — and the resulting failure names nothing useful. A swift.org
# toolchain driving Xcode's SDK opens with
#
#     error: unknown argument: '-target-arch-variant'
#
# and then thousands of lines of apparent nonsense, `cannot find 'Data' in
# scope` in a file whose first line imports Foundation. Nothing in that points
# at the toolchain, and the obvious reading — that the source is broken — is
# wrong.
#
# It has to be Xcode's specifically, not merely a working Swift.
# `AppleOnDeviceProvider` uses the @Generable and @Guide macros, which Swift
# expands with a compiler plugin Apple ships only inside Xcode. See the
# Building section of the README.
find_swift() {
    local developer swift

    # Which Xcode, honouring DEVELOPER_DIR and xcode-select — that is how
    # anyone with more than one installed chooses between them.
    developer="$(xcode-select -p 2>/dev/null || true)"
    if [ -z "$developer" ]; then
        echo "No Xcode is selected, and Hoot cannot be built without one." >&2
        echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
        return 1
    fi

    # The Command Line Tools are a complete Swift and still not enough: they
    # ship no macro plugins, so the build fails on FoundationModelsMacros
    # rather than on anything to do with what is missing.
    case "$developer" in
        */CommandLineTools*)
            echo "The Command Line Tools are selected, and Hoot needs full Xcode." >&2
            echo "The @Generable macro is expanded by a compiler plugin that only" >&2
            echo "ships inside Xcode, so the build would fail on the macro instead." >&2
            echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
            return 1
            ;;
    esac

    # TOOLCHAINS is cleared deliberately. It is the one setting that can point
    # xcrun at a swift.org toolchain inside a perfectly good Xcode, which is
    # the failure above wearing a disguise.
    swift="$(TOOLCHAINS='' xcrun --find swift 2>/dev/null || true)"
    if [ -z "$swift" ] || [ ! -x "$swift" ]; then
        echo "Xcode is selected at $developer but has no usable swift." >&2
        echo "Opening Xcode once will finish installing its components." >&2
        return 1
    fi

    # Last check, and the one that catches the case this file was written for:
    # the compiler must live inside the Xcode that was selected. Anything else
    # is a toolchain that has quietly won, and it will not build this project.
    case "$swift" in
        "$developer"/*) ;;
        *)
            echo "The Swift on this machine is not Xcode's:" >&2
            echo "  $swift" >&2
            echo "Hoot needs the one inside $developer, because the @Generable" >&2
            echo "macro is expanded by a plugin only Xcode ships." >&2
            echo "Unset TOOLCHAINS, or take the other toolchain off PATH." >&2
            return 1
            ;;
    esac

    echo "$swift"
}
