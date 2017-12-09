//
//  AKPlayer.swift
//  AudioKit
//
//  Created by Ryan Francesconi, revision history on Github.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import AVFoundation

/**
 AKPlayer is meant to be a simple yet powerful audio player that just works. It supports
 scheduling of sounds, looping, fading, and reversing. Players can be locked to a common
 clock as well as video by using hostTime in the various play functions.

 A locked video function would resemble:
 ```
 func videoPlay(at time: TimeInterval = 0, hostTime: UInt64 = 0 ) {
 let cmHostTime = CMClockMakeHostTimeFromSystemUnits(hostTime)
 let cmVTime = CMTimeMakeWithSeconds(time, 1000000)
 let futureTime = CMTimeAdd(cmHostTime, cmVTime)
 videoPlayer.setRate(1, time: kCMTimeInvalid, atHostTime: futureTime)
 }
 ```

 Basic usage looks like:
 ```
 guard let player = AKPlayer(url: url) else { return }
 player.completionHandler = { Swift.print("Done") }

 // Loop Options
 player.loop.start = 1
 player.loop.end = 3
 player.isLooping = true

 player.play()
 ```

 Please note that pre macOS 10.13 / iOS 11 the completionHandler isn't sample accurate. It's pretty close though.
 */
public class AKPlayer: AKNode { //AKTiming

    /// How the player should handle audio. If buffering, it will load the audio data into
    /// an internal buffer and play from ram. If not, it will play the file from disk.
    /// Dynamic buffering will only load the audio if it needs to for processing reasons.
    public enum BufferingType {
        case dynamic, always, never
    }

    //TODO: allow for different exponential curve slopes, implement other types
    public enum FadeType {
        case exponential //, linear, logarithmic
    }

    public struct Loop {
        public var start: Double = 0
        public var end: Double = 0
    }

    public struct Fade {
        public static var defaultStartGain: Double = 0.001

        var needsUpdate: Bool = false

        public var inTime: Double = 0 {
            willSet {
                if newValue != inTime { needsUpdate = true }
            }
        }

        public var inStartGain: Double = defaultStartGain {
            willSet {
                if newValue != inStartGain { needsUpdate = true }
            }
        }

        public var outTime: Double = 0 {
            willSet {
                if newValue != outTime { needsUpdate = true }
            }
        }

        public var outStartGain: Double = 1 {
            willSet {
                if newValue != outStartGain { needsUpdate = true }
            }
        }

        public var type: AKPlayer.FadeType = .exponential {
            willSet {
                if newValue != type { needsUpdate = true }
            }
        }
    }

    // MARK: - Private Parts

    // The underlying player node
    private let playerNode = AVAudioPlayerNode()
    private var mixer = AVAudioMixerNode()
    private var buffer: AVAudioPCMBuffer?
    private var startingFrame: AVAudioFramePosition?
    private var endingFrame: AVAudioFramePosition?

    // these timers will go away when AudioKit is built for 10.13
    // in that case the real completion handlers of the scheduling can be used.
    // Pre 10.13 the completion handlers are inaccurate to the point of unusable.
    private var prerollTimer: Timer?
    private var completionTimer: Timer?

    // MARK: - public properties
    open var completionHandler: AKCallback?

    /// Sets if the player should buffer dynamically, always or never
    /// Not buffering means playing from disk, buffering is playing from RAM
    open var buffering: BufferingType = .dynamic {
        didSet {
            if buffering == .always {
                preroll()
            }
        }
    }

    /// The internal audio file
    public private (set) var audioFile: AVAudioFile?

    /// The duration of the loaded audio file
    open var duration: Double {
        return audioFile?.duration ?? 0
    }

    /// holds characteristics about the fade options. Using fades will set the player to buffering
    open var fade = Fade()

    /// holds characteristics about the looping options
    open var loop = Loop()

    /// Volume 0.0 -> 1.0, default 1.0
    open var volume: Float {
        get { return playerNode.volume }
        set { playerNode.volume = newValue }
    }

    /// Left/Right balance -1.0 -> 1.0, default 0.0
    open var pan: Float {
        get { return playerNode.pan }
        set { playerNode.pan = newValue }
    }

    /// get or set the current time of the player. If playing it will scrub to that point.
    /// If buffered it will preroll.
    public var startTime: Double = 0 {
        didSet {
            startTime = max(0, startTime)

            // Should playback restart automatically?
            if isPlaying {
                stop()
                play()
            }
        }
    }

    public var endTime: Double = 0 {
        didSet {
            if endTime == 0 { endTime = duration }
            endTime = min(endTime, duration)
        }
    }

    /// - Returns: Current time of the player in seconds.
    /// Use setTime() or startTime to set the time
    open var currentTime: Double {
        return position(at: nil)
    }

    // MARK: - public options

    /// true if any fades have been set
    open var isFaded: Bool {
        return fade.inTime > 0 || fade.outTime > 0
    }

    /// true if the player is buffering audio rather than playing from disk
    open var isBuffered: Bool {
        if buffering == .never {
            return false
        } else {
            return isReversed || isFaded || buffering == .always
        }
    }

    open var isLooping: Bool = false

    /// Reversing the audio will set the player to buffering
    open var isReversed: Bool = false {
        didSet {

            let wasPlaying = isPlaying
            stop()

            if isLooping {
                preroll(from: loop.start, to: loop.end)
            }

            if wasPlaying {
                //play()
            }
        }
    }

    open var isPlaying: Bool {
        return playerNode.isPlaying
    }

    // MARK: - Initialization

    /// Create a player from a URL
    public convenience init?(url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            return nil
        }
        do {
            let avfile = try AVAudioFile(forReading: url)
            self.init(audioFile: avfile)
            return
        } catch {
            Swift.print(error)
        }
        return nil
    }

    /// Create a player from an AVAudioFile
    public convenience init(audioFile: AVAudioFile) {
        self.init()
        self.audioFile = audioFile
        initialize()
    }

    public override init() {
        super.init(avAudioNode: mixer, attach: false)
    }

    private func initialize() {
        guard audioFile != nil else { return }

        if playerNode.engine == nil {
            AudioKit.engine.attach(playerNode)
        }
        if mixer.engine == nil {
            AudioKit.engine.attach(mixer)
        }

        playerNode.disconnectOutput()

        let format = AVAudioFormat(standardFormatWithSampleRate: audioFile!.sampleRate,
                                   channels: audioFile!.channelCount)

        AudioKit.connect(playerNode, to: mixer, format: format)

        loop.start = 0
        loop.end = duration
        preroll(from: 0)
    }

    // MARK: - Loading

    /// Replace the contents of the player with this url
    public func load(url: URL) throws {
        self.audioFile = try AVAudioFile(forReading: url)
        initialize()
    }

    /// Mostly applicable to buffered players, this loads the buffer and gets it ready to play.
    /// Otherwise it just sets the startTime and endTime
    public func preroll(from startingTime: Double = 0, to endingTime: Double = 0) {
        var from = startingTime
        let to = endingTime

        if from > to {
            from = 0
        }

        startTime = from
        endTime = to

        Swift.print("preroll from \(startTime) to \(endTime)")

        guard isBuffered else { return }
        updateBuffer()
    }

    // MARK: - Playback

    /// Play entire file right now
    public func play() {
        play(from: startTime, to: endTime, at: nil, hostTime: nil)
    }

    /// Play segments of a file
    public func play(from startingTime: Double, to endingTime: Double = 0) {
        var to = endingTime
        if to == 0 {
            to = endTime
        }
        play(from: startingTime, to: to, at: nil, hostTime: nil)
    }

    /// Play file using previously set startTime and endTime at some point in the future
    public func play(at audioTime: AVAudioTime?) {
        play(at: audioTime, hostTime: nil)
    }

    /// Play file using previously set startTime and endTime at some point in the future with a hostTime reference
    public func play(at audioTime: AVAudioTime?, hostTime: UInt64?) {
        play(from: startTime, to: endTime, at: audioTime, hostTime: hostTime)
    }

    /// Play file using previously set startTime and endTime at some point in the future specified in seconds
    /// with a hostTime reference
    public func play(when scheduledTime: Double, hostTime: UInt64?) {
        play(from: startTime, to: endTime, when: scheduledTime, hostTime: hostTime)
    }

    public func play(from startingTime: Double,
                     to endingTime: Double,
                     when scheduledTime: Double,
                     hostTime: UInt64? = nil) {
        let refTime = hostTime != nil ? hostTime! : mach_absolute_time()
        let avTime = AKPlayer.secondsToAVAudioTime(hostTime: refTime, time: scheduledTime)
        play(from: startingTime, to: endingTime, at: avTime, hostTime: refTime)
    }

    /// Play using full options. Last in the convenience play chain, all play() commands will end up here
    public func play(from startingTime: Double, to endingTime: Double, at audioTime: AVAudioTime?, hostTime: UInt64?) {
        preroll(from: startingTime, to: endingTime)
        schedule(at: audioTime)
        playerNode.play()

        completionTimer?.invalidate()
        prerollTimer?.invalidate()

        let prerollTime = audioTime != nil ?
            AKPlayer.audioTimeToSeconds(hostTime: hostTime!, audioTime: audioTime!) : 0
        if prerollTime > 0 {
            //Swift.print("prerollTime: \(prerollTime)")
            prerollTimer = Timer.scheduledTimer(timeInterval: prerollTime,
                                                target: self,
                                                selector: #selector(AKPlayer.startCompletionTimer),
                                                userInfo: nil,
                                                repeats: false)
        } else {
            startCompletionTimer()
        }
    }

    /// Stop playback and cancel any pending scheduling or completion events
    public func stop() {
        playerNode.stop()
        completionTimer?.invalidate()
        prerollTimer?.invalidate()
    }

    ///MARK:- Private Scheduling

    // these timers will go away when AudioKit is built for 10.13
    // in that case the real completion handlers of the scheduling can be used.
    // Pre 10.13 the completion handlers are inaccurate to the point of unusable.
    @objc private func startCompletionTimer() {
        var segmentDuration = endTime - startTime
        if isLooping && loop.end > 0 {
            segmentDuration = loop.end - startTime
        }
        completionTimer = Timer.scheduledTimer(timeInterval: segmentDuration,
                                               target: self,
                                               selector: #selector(AKPlayer.handleComplete),
                                               userInfo: nil,
                                               repeats: false)
    }

    // this will become the method in the scheduling completionHandler >= 10.13
    @objc private func handleComplete() {
        //Swift.print("COMPLETE: \(audioFile?.url.lastPathComponent)")
        completionHandler?()

        if isLooping {
            startTime = loop.start
        }
    }

    private func schedule(at audioTime: AVAudioTime?) {
        if isBuffered {
            scheduleBuffer(at: audioTime)
        } else {
            scheduleSegment(at: audioTime)
        }

    }

    private func scheduleBuffer(at audioTime: AVAudioTime?) {
        guard let buffer = buffer else { return }

        if playerNode.outputFormat(forBus: 0) != buffer.format {
            Swift.print("ERROR: Formats don't match: \(playerNode.outputFormat(forBus: 0)) vs \(buffer.format)")
            initialize()
        }

        playerNode.scheduleBuffer(buffer,
                                  at: audioTime,
                                  options: [.interrupts],
                                  completionHandler: nil) // these completionHandlers are inaccurate pre 10.13
        playerNode.prepare(withFrameCount: buffer.frameLength)
    }

    // play from disk rather than ram
    private func scheduleSegment(at audioTime: AVAudioTime?) {
        guard let audioFile = audioFile else { return }

        let startFrame = AVAudioFramePosition(startTime * audioFile.sampleRate)
        var endFrame = AVAudioFramePosition(endTime * audioFile.sampleRate)

        if endFrame == 0 {
            endFrame = audioFile.samplesCount
        }

        let frameCount = (audioFile.samplesCount - startFrame) - (audioFile.samplesCount - endFrame)

        playerNode.scheduleSegment(audioFile,
                                   startingFrame: startFrame,
                                   frameCount: AVAudioFrameCount(frameCount),
                                   at: audioTime,
                                   completionHandler: nil) // these completionHandlers are inaccurate pre 10.13
        playerNode.prepare(withFrameCount: AVAudioFrameCount(frameCount))
    }

    /// Future AKTiming

    /// Time in seconds at a given audio time
    ///
    /// - parameter audioTime: A time in the audio render context.
    /// - Returns: Time in seconds in the context of the player's timeline.
    ///
    public func position(at audioTime: AVAudioTime?) -> Double {
        guard let playerTime = playerNode.playerTime(forNodeTime: audioTime ?? AVAudioTime.now()) else {
            return startTime
        }
        return startTime + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    /// Audio time for a given time.
    ///
    /// - Parameter time: Time in seconds in the context of the player's timeline.
    /// - Returns: A time in the audio render context.
    ///
    public func audioTime(at position: Double) -> AVAudioTime? {
        let sampleRate = playerNode.outputFormat(forBus: 0).sampleRate
        let sampleTime = (position - startTime) * sampleRate
        let playerTime = AVAudioTime(sampleTime: AVAudioFramePosition(sampleTime), atRate: sampleRate)
        return playerNode.nodeTime(forPlayerTime: playerTime)
    }

    //    public func setPosition(_ position: Double) {
    //        startTime = position
    //    }

    // MARK: - Buffering routines

    /// Fills the buffer with data read from audioFile
    private func updateBuffer() {
        if !isBuffered { return }

        guard let audioFile = audioFile else { return }

        let fileFormat = audioFile.fileFormat
        let processingFormat = audioFile.processingFormat

        var startFrame = AVAudioFramePosition(startTime * fileFormat.sampleRate)
        var endFrame = AVAudioFramePosition(endTime * fileFormat.sampleRate)

        // if we are going to be reversing the buffer, we need to think ahead a bit
        // since the edit points would be reversed as well, we swap them here:
        if isReversed {
            let revEndTime = duration - startTime
            let revStartTime = endTime > 0 ? duration - endTime : duration

            startFrame = AVAudioFramePosition(revStartTime * fileFormat.sampleRate)
            endFrame = AVAudioFramePosition(revEndTime * fileFormat.sampleRate)
        }

        let updateNeeded = (buffer == nil || startFrame != startingFrame || endFrame != endingFrame || fade.needsUpdate)

        if !updateNeeded {
            Swift.print("updateBuffer() no update needed.")
            return
        }

        guard audioFile.samplesCount > 0  else {
            AKLog("ERROR updateBuffer: Could not set PCM buffer -> " +
                "\(audioFile.fileNamePlusExtension) samplesCount = 0.")
            return
        }
        let frameCount = AVAudioFrameCount(endFrame - startFrame)
        //let totalFrames = AVAudioFrameCount(audioFile.length)
        buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount )

        do {
            audioFile.framePosition = startFrame
            // read the requested frame count from the file
            try audioFile.read(into: buffer!, frameCount: frameCount)

        } catch let err as NSError {
            AKLog("ERROR AKPlayer: Couldn't read data into buffer. \(err)")
            return
        }

        // Now, we'll reverse the data in the buffer if specified
        if isReversed {
            reverseBuffer()
        }

        // Same idea with fades
        if isFaded {
            fadeBuffer()
            fade.needsUpdate = false
        }

        // these are only stored to check if the buffer needs to be updated in subsequent fills
        self.startingFrame = startFrame
        self.endingFrame = endFrame

        Swift.print("updateBuffer() read from \(startTime) to \(endTime)")
    }

    // Apply sample level fades to the internal buffer.
    // TODO: add other fade curves or ditch this method in favor of Audio Unit based fading.
    // That is appealing as it will work with file playback as well as buffer
    private func fadeBuffer() {
        if fade.inTime == 0 && fade.outTime == 0 {
            return
        }
        AKLog("fadeBuffer() inTime: \(fade.inTime) outTime: \(fade.outTime)")

        guard isBuffered, let buffer = self.buffer, let audioFile = self.audioFile else { return }

        let fadedBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity)
        let length: AVAudioFrameCount = buffer.frameLength

        // initial starting point for the gain, if there is a fade in, start it at .01 otherwise at 1
        var gain: Double = fade.inTime > 0 ? fade.inStartGain : 1.0

        let sampleTime: Double = 1.0 / audioFile.sampleRate

        //exponential fade type

        // from -20db?
        let fadeInPower: Double = exp(log(10) * sampleTime / fade.inTime)

        // for decay to x% amplitude (-dB) over the given decay time
        let fadeOutPower: Double = exp(-log(25) * sampleTime / fade.outTime)

        // where in the buffer to end the fade in
        let fadeInSamples = Int(audioFile.sampleRate * fade.inTime)
        // where in the buffer to start the fade out
        let fadeOutSamples = Int(Double(length) - (audioFile.sampleRate * fade.outTime))

        // i is the index in the buffer
        for i in 0 ..< Int(length) {
            // n is the channel
            for n in 0 ..< Int(buffer.format.channelCount) {

                if i <= fadeInSamples && fade.inTime > 0 {
                    gain *= fadeInPower
                } else if i >= fadeOutSamples && fade.outTime > 0 {
                    if i == fadeOutSamples {
                        gain = fade.outStartGain
                    }
                    gain *= fadeOutPower
                } else {
                    gain = 1.0
                }

                //sanity check
                if gain > 1 {
                    gain = 1
                }

                let sample = buffer.floatChannelData![n][i] * Float(gain)
                fadedBuffer?.floatChannelData?[n][i] = sample
            }
        }

        // set the buffer now to be the faded one
        self.buffer = fadedBuffer
        // update this
        self.buffer?.frameLength = length
    }

    // Read the buffer in backwards
    fileprivate func reverseBuffer() {
        if buffer == nil {
            //updateBuffer()
        }
        guard isBuffered, let buffer = self.buffer else { return }

        let reversedBuffer = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        )

        var j: Int = 0
        let length = buffer.frameLength
        //AKLog("reverse() preparing \(length) frames")

        // i represents the normal buffer read in reverse
        for i in (0 ..< Int(length)).reversed() {
            // n is the channel
            for n in 0 ..< Int(buffer.format.channelCount) {
                // we write the reverseBuffer via the j index
                reversedBuffer?.floatChannelData?[n][j] = buffer.floatChannelData?[n][i] ?? 0.0
            }
            j += 1
        }

        reversedBuffer?.frameLength = length

        // set the buffer now to be the reverse one
        self.buffer = reversedBuffer

        AKLog("Buffer reversed: \(isReversed)")
    }

    // Disconnect the node
    override open func disconnect() {
        stop()
        audioFile = nil
        buffer = nil
        AudioKit.detach(nodes: [mixer, playerNode])
    }

    deinit {
        AKLog("* deinit AKPlayer")
    }

    // MARK: - Static Methods

    /// convert an AVAudioTime object to seconds with a hostTime reference
    open class func audioTimeToSeconds(hostTime: UInt64, audioTime: AVAudioTime) -> Double {
        return AVAudioTime.seconds(forHostTime: audioTime.hostTime - hostTime)
    }

    // convert seconds to AVAudioTime with a hostTime reference
    open class func secondsToAVAudioTime(hostTime: UInt64, time: Double) -> AVAudioTime {
        // Find the conversion factor from host ticks to seconds
        var timebaseInfo = mach_timebase_info()
        mach_timebase_info(&timebaseInfo)
        let hostTimeToSecFactor = Double(timebaseInfo.numer) / Double(timebaseInfo.denom) / Double(NSEC_PER_SEC)
        let out = AVAudioTime(hostTime: hostTime + UInt64(time / hostTimeToSecFactor))
        return out
    }

    open class func formatSeconds( _ time: TimeInterval, frameRate: Float = 0 ) -> String {
        if time.isNaN || time.isInfinite || time.isSignalingNaN {
            return String("-")
        }
        var t = time

        var preroll = ""
        if time < 0 {
            preroll = "-"
        }

        t = abs(t)

        //calculate the minutes in elapsed time.
        let minutes = Int(t / 60.0)
        t -= (TimeInterval(minutes) * 60)

        //calculate the seconds in elapsed time.
        let seconds = Int(t)
        t -= TimeInterval(seconds)

        //find out the fraction of milliseconds to be displayed.
        let mult = frameRate > 0 ? frameRate : 100
        let fraction = Int(t * mult)
        let strMinutes = String(format: "%02d", minutes)
        let strSeconds = String(format: "%02d", seconds)
        let strFraction = String(format: "%02d", fraction)

        let out = "\(preroll)\(strMinutes):\(strSeconds):\(strFraction)"
        return out
    }

    open class func formatTimecode(frame: Int, fps: Float) -> String {
        let ff = Int(Float(frame).truncatingRemainder(dividingBy: fps))
        let seconds = Int(Float(frame - ff) / fps)
        let ss = seconds % 60
        let mm = (seconds % 3600) / 60
        let timecode = [String(format: "%02d", mm), String(format: "%02d", ss), String(format: "%02d", ff)];
        return timecode.joined(separator: ":")
    }

    open class func simpleFormatSeconds( _ time: TimeInterval ) -> String {
        var t = time

        var preroll = ""
        if time < 0 {
            preroll = "-"
        }

        t = abs(t)

        //calculate the minutes in elapsed time.
        let minutes = Int(t / 60.0)
        t -= (TimeInterval(minutes) * 60)

        //calculate the seconds in elapsed time.
        let seconds = Int(t)
        t -= TimeInterval(seconds)
        let strSeconds = String(format: "%02d", seconds)
        let out = "\(preroll)\(minutes):\(strSeconds)"
        return out
    }
}

