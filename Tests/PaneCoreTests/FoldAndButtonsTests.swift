import CoreGraphics
import Foundation
import Testing

@testable import PaneCore

/// Board 28: the device kind from `config.ini`, the fold control's rules and the buttons per kind.
@Suite struct DeviceKindTests {
    /// The keys a `pixel_9_pro_fold` AVD carries (emulator 37.3.9, android-36.1 image).
    static let bookFold = """
        hw.device.name=pixel_9_pro_fold
        tag.id=google_apis
        hw.lcd.width=2076
        hw.lcd.height=2152
        hw.lcd.density=390
        hw.sensor.hinge=yes
        hw.sensor.hinge.count=1
        hw.sensor.hinge.type=1
        hw.sensor.hinge.sub_type=1
        hw.sensor.hinge.ranges=0-180
        hw.sensor.hinge.areas=1038-0-0-2152
        hw.sensor.posture_list=1, 2, 3
        hw.sensor.hinge_angles_posture_definitions=0-30, 30-150, 150-180
        hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture=1
        hw.sensor.hinge.resizable.config=1
        hw.displayRegion.0.1.xOffset=0
        hw.displayRegion.0.1.yOffset=0
        hw.displayRegion.0.1.width=1080
        hw.displayRegion.0.1.height=2424
        """

    /// The SDK's "8in Foldable": folds outwards, so the screen folds at Flipped.
    static let foldOut = """
        hw.device.name=8in Foldable
        tag.id=google_apis
        hw.lcd.width=2200
        hw.lcd.height=2480
        hw.lcd.density=420
        hw.sensor.hinge=yes
        hw.sensor.hinge.count=1
        hw.sensor.hinge.type=1
        hw.sensor.posture_list=3, 4
        hw.sensor.hinge_angles_posture_definitions=180-330, 330-360
        hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture=4
        hw.displayRegion.0.1.width=1148
        hw.displayRegion.0.1.height=2480
        """

    /// The Resizable AVD carries a hinge block but is out of scope.
    static let resizable = """
        hw.device.name=resizable
        tag.id=google_apis
        hw.lcd.width=1080
        hw.lcd.height=2400
        hw.lcd.density=420
        hw.sensor.hinge=yes
        hw.sensor.hinge.count=1
        hw.sensor.posture_list=1, 2, 3
        hw.sensor.hinge_angles_posture_definitions=0-30, 30-150, 150-180
        hw.resizable.configs=phone-0-1080-2400-420, foldable-1-2208-1840-420, tablet-2-1920-1200-240
        """

    static let tablet = """
        hw.device.name=pixel_tablet
        tag.id=google_apis
        hw.lcd.width=2560
        hw.lcd.height=1600
        hw.lcd.density=320
        hw.sensor.hinge=no
        hw.sensor.hinge.count=0
        """

    /// A large automotive screen: not a tablet, whatever its size.
    static let automotive = """
        hw.device.name=automotive_1408p_landscape_with_google_apis
        tag.id=android-automotive
        hw.lcd.width=1408
        hw.lcd.height=792
        hw.lcd.density=160
        """

    static let phone = """
        hw.device.name=pixel_8
        tag.id=google_apis
        hw.lcd.width=1080
        hw.lcd.height=2400
        hw.lcd.density=420
        hw.sensor.hinge=no
        hw.sensor.hinge.count=0
        hw.sensor.hinge.resizable.config=1
        """

    @Test func aBookFoldIsAFoldableWithItsPostures() {
        let profile = DeviceProfile.parse(configIni: Self.bookFold)
        #expect(profile.kind == .foldable)
        #expect(profile.fold?.postures == [.closed, .halfOpen, .open])
        #expect(profile.fold?.foldPosture == .closed)
        #expect(profile.fold?.outerScreenSize == PixelSize(width: 1080, height: 2424))
        #expect(profile.fold?.hingeType == 1)
    }

    @Test func aFoldOutDeviceFoldsAtFlipped() {
        let profile = DeviceProfile.parse(configIni: Self.foldOut)
        #expect(profile.kind == .foldable)
        #expect(profile.fold?.postures == [.open, .flipped])
        #expect(profile.fold?.foldPosture == .flipped)
    }

    @Test func theResizableAVDIsAPhone() {
        let profile = DeviceProfile.parse(configIni: Self.resizable)
        #expect(profile.kind == .phone)
        #expect(profile.fold == nil)
    }

    @Test func aHingeNeedsMatchingPostureDefinitions() {
        let mismatched = Self.bookFold.replacingOccurrences(
            of: "0-30, 30-150, 150-180", with: "0-30, 30-180")
        #expect(DeviceProfile.parse(configIni: mismatched).fold == nil)
        let noCount = Self.bookFold.replacingOccurrences(of: "hinge.count=1", with: "hinge.count=0")
        #expect(DeviceProfile.parse(configIni: noCount).fold == nil)
        let noList = Self.bookFold.replacingOccurrences(of: "posture_list=1, 2, 3", with: "posture_list=")
        // Without postures it's no foldable; its 851 dp inner screen then makes it a tablet.
        #expect(DeviceProfile.parse(configIni: noList).fold == nil)
        #expect(DeviceProfile.parse(configIni: noList).kind == .tablet)
    }

    @Test func aTabletIsAHandheldImageWithA600dpShortSide() {
        #expect(DeviceProfile.parse(configIni: Self.tablet).kind == .tablet)
        #expect(DeviceProfile.parse(configIni: Self.tablet).fold == nil)
        #expect(DeviceProfile.parse(configIni: Self.automotive).kind == .phone)
        #expect(DeviceProfile.parse(configIni: Self.phone).kind == .phone)
        // 599 dp is still a phone; 600 dp is a tablet.
        #expect(!DeviceProfile.isTablet(tag: "default", screenSize: PixelSize(width: 599, height: 900), density: 160))
        #expect(DeviceProfile.isTablet(tag: "default", screenSize: PixelSize(width: 900, height: 600), density: 160))
        #expect(!DeviceProfile.isTablet(tag: nil, screenSize: PixelSize(width: 2560, height: 1600), density: 320))
    }
}

@Suite struct FoldControlTests {
    private let fold = FoldProfile(postures: [.closed, .halfOpen, .open], foldPosture: .closed)

    @Test func foldReadsUnfoldOnlyAtTheFoldPosture() {
        #expect(fold.foldTitle(current: nil) == "Fold")
        #expect(fold.foldTitle(current: .open) == "Fold")
        #expect(fold.foldTitle(current: .halfOpen) == "Fold")
        #expect(fold.foldTitle(current: .closed) == "Unfold")
    }

    @Test func foldTogglesBetweenTheFoldPostureAndOpen() {
        #expect(fold.toggled(from: nil) == .closed)
        #expect(fold.toggled(from: .open) == .closed)
        #expect(fold.toggled(from: .halfOpen) == .closed)
        #expect(fold.toggled(from: .closed) == .open)
        let foldOut = FoldProfile(postures: [.open, .flipped], foldPosture: .flipped)
        #expect(foldOut.toggled(from: .open) == .flipped)
        #expect(foldOut.toggled(from: .flipped) == .open)
    }

    @Test func posturesMapToTheEmulatorsValues() {
        #expect(EmulatorConnection.postureValue(.closed) == .postureClosed)
        #expect(EmulatorConnection.postureValue(.halfOpen) == .postureHalfOpened)
        #expect(EmulatorConnection.postureValue(.open) == .postureOpened)
        #expect(EmulatorConnection.postureValue(.flipped) == .postureFlipped)
        #expect(EmulatorConnection.postureValue(.tent) == .postureTent)
    }

    @Test func postureNamesAndTheRefusal() {
        #expect(DevicePosture.allCases.map(\.title) == ["Closed", "Half-open", "Open", "Flipped", "Tent"])
        #expect(DevicePosture.halfOpen.menuBarTitle == "Half-Open")
        #expect(DevicePosture.closed.menuBarTitle == "Closed")
        #expect(FoldProfile.refusal == "Couldn't change the posture.")
    }
}

@Suite struct FrameButtonsPerKindTests {
    private static let phoneSet = DeviceFrameLayoutTests.boardSpec.buttons
    private static var tabletSpec: FrameSpec {
        var spec = DeviceFrameLayoutTests.boardSpec
        spec.buttons = phoneSet.map { $0.placed(on: .top, from: .right) }
        return spec
    }
    private static let pixelTablet = PixelSize(width: 2560, height: 1600)

    @Test func aTabletsButtonsSitOnTheTopEdgeFromTheRightEnd() {
        let layout = DeviceFrameLayout(spec: Self.tabletSpec, deviceSize: Self.pixelTablet)
        // Body 1140 × 720, one button depth below the 52 pt title row, 24 pt in.
        #expect(layout.bodyRect == CGRect(x: 24, y: 55, width: 1140, height: 720))
        #expect(layout.windowContentSize == CGSize(width: 1188, height: 799))
        let byButton = Dictionary(uniqueKeysWithValues: layout.buttons.map { ($0.button, $0) })
        // The same points as a phone's, measured from the top right corner.
        #expect(byButton[.power]?.visibleRect == CGRect(x: 958, y: 52, width: 56, height: 3))
        #expect(byButton[.volumeUp]?.visibleRect == CGRect(x: 886, y: 52, width: 46, height: 3))
        #expect(byButton[.volumeDown]?.visibleRect == CGRect(x: 840, y: 52, width: 46, height: 3))
        #expect(byButton[.power]?.hitRect == CGRect(x: 954, y: 41, width: 64, height: 14))
        #expect(byButton[.volumeUp]?.hitRect == CGRect(x: 886, y: 41, width: 50, height: 14))
        #expect(byButton[.volumeDown]?.hitRect == CGRect(x: 836, y: 41, width: 50, height: 14))
        #expect(layout.buttons.allSatisfy { $0.edge == .top })
        #expect(byButton[.power]?.roundedCorners == [.topLeft, .topRight])
        #expect(byButton[.volumeUp]?.roundedCorners == [.topRight])
        #expect(byButton[.volumeDown]?.roundedCorners == [.topLeft])
        // VoiceOver reads them left to right.
        #expect(layout.buttonsInReadingOrder.map(\.button) == [.volumeDown, .volumeUp, .power])
    }

    @Test func aTurnedTabletsButtonsTurnWithTheBody() {
        let left = DeviceFrameLayout(spec: Self.tabletSpec, deviceSize: Self.pixelTablet, quadrants: 1)
        #expect(left.buttons.allSatisfy { $0.edge == .left })
        // Power nearest the top, then volume up, then down.
        #expect(left.buttonsInReadingOrder.map(\.button) == [.power, .volumeUp, .volumeDown])
        let power = left.buttons.first { $0.button == .power }!
        #expect(power.visibleRect.maxX == left.bodyRect.minX)
        #expect(power.visibleRect.minY == left.bodyRect.minY + 150)
        let upsideDown = DeviceFrameLayout(spec: Self.tabletSpec, deviceSize: Self.pixelTablet, quadrants: 2)
        #expect(upsideDown.buttons.allSatisfy { $0.edge == .bottom })
        let right = DeviceFrameLayout(spec: Self.tabletSpec, deviceSize: Self.pixelTablet, quadrants: 3)
        #expect(right.buttons.allSatisfy { $0.edge == .right })
        #expect(right.buttonsInReadingOrder.map(\.button) == [.volumeDown, .volumeUp, .power])
    }

    @Test func aPhonesButtonsAreUnchangedAndReadTopToBottom() {
        let layout = DeviceFrameLayout(
            spec: DeviceFrameLayoutTests.boardSpec, deviceSize: PixelSize(width: 1080, height: 2400))
        #expect(layout.buttons.allSatisfy { $0.edge == .right })
        #expect(layout.buttonsInReadingOrder.map(\.button) == [.power, .volumeUp, .volumeDown])
        let turned = DeviceFrameLayout(
            spec: DeviceFrameLayoutTests.boardSpec, deviceSize: PixelSize(width: 1080, height: 2400), quadrants: 1)
        #expect(turned.buttons.allSatisfy { $0.edge == .top })
        #expect(turned.buttonsInReadingOrder.map(\.button) == [.power, .volumeUp, .volumeDown])
    }

    @Test func aFoldKeepsItsButtonsStillThroughTheFold() {
        // Board 27 holds the screen height through a fold, so offset × scale doesn't move.
        let open = DeviceFrameLayout(
            spec: DeviceFrameLayoutTests.boardSpec, deviceSize: PixelSize(width: 2076, height: 2152), screenHeight: 600)
        let shut = DeviceFrameLayout(
            spec: DeviceFrameLayoutTests.boardSpec, deviceSize: PixelSize(width: 1080, height: 2424), screenHeight: 600)
        #expect(open.buttons.map(\.visibleRect.minY) == shut.buttons.map(\.visibleRect.minY))
        #expect(open.buttons.map(\.edge) == shut.buttons.map(\.edge))
    }
}
