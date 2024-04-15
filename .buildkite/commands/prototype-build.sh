#!/bin/bash -eu

echo "--- :rubygems: Setting up Gems"
install_gems

echo "--- :cocoapods: Setting up Pods"
install_cocoapods

echo "--- :swift: Setting up Swift Packages"
install_swiftpm_dependencies

echo "--- :closed_lock_with_key: Installing Secrets"
bundle exec fastlane run configure_apply

echo "--- Test unstable internal pods annotation"
bundle exec fastlane test_check_pods_references

echo "--- :hammer_and_wrench: Building"
bundle exec fastlane build_and_upload_prototype_build
