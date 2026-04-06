#!/bin/bash
set -e

# Install xcodegen if not available
if ! command -v xcodegen &> /dev/null; then
    brew install xcodegen
fi

# Generate Xcode project from project.yml
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
