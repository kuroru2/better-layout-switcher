import Foundation
import CoreGraphics

// Minimal bridge to one private function we need: reading current brightness
// to gate whether F1/F2 should adjust XDR boost (only when user is already
// at max system brightness, matching Vivid's UX). Lives in
// /System/Library/PrivateFrameworks/DisplayServices.framework. The Swift
// name is lowercased so SwiftLint's identifier_name rule is happy;
// @_silgen_name links to the actual C symbol unchanged.
@_silgen_name("DisplayServicesGetBrightness")
func displayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32
