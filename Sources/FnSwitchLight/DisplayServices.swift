import Foundation
import CoreGraphics

/// Minimal bridge to one private function we need: reading current brightness
/// to gate whether F1/F2 should adjust XDR boost (only when user is already
/// at max system brightness, matching Vivid's UX). Lives in
/// /System/Library/PrivateFrameworks/DisplayServices.framework.
@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32
