import AVFoundation
import Foundation
import Observation

/// A voz do treino. Este é o único arquivo que importa AVFoundation: todo o
/// resto fala com a fala por aqui, sem tocar em sessão de áudio direto.
@MainActor
@Observable
public final class IdiomasSpeech: NSObject, AVSpeechSynthesizerDelegate {
  /// Taxa de aprendiz, perto do padrão da voz. Mais devagar que isso a frase
  /// alemã perde o ritmo e vira sílaba solta.
  private static let learnerRate: Float = 0.5

  private let synthesizer = AVSpeechSynthesizer()
  public private(set) var isGermanVoiceAvailable = false
  public private(set) var micDenied = false
  /// Segue o delegado do sintetizador, para o botão de ouvir virar parar
  /// enquanto a voz fala.
  public private(set) var isSpeaking = false

  override public init() {
    super.init()
    synthesizer.delegate = self
  }

  /// Confere a voz alemã sem travar a entrada no hub. A lista de vozes pode
  /// demorar na primeira chamada, então isto roda solto e a tela segue sem ela.
  public func checkVoiceAvailability() {
    Task.detached { [weak self] in
      let available = Self.germanVoice() != nil
      await MainActor.run { self?.isGermanVoiceAvailable = available }
    }
  }

  public func speak(_ text: String) {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return }
    setPlaybackSession()
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: clean)
    utterance.voice = Self.germanVoice()
    utterance.rate = Self.learnerRate
    utterance.pitchMultiplier = 1
    synthesizer.speak(utterance)
  }

  public func stop() {
    synthesizer.stopSpeaking(at: .immediate)
  }

  /// Liga ou desliga a escuta do treino. Armar para a síntese antes, porque
  /// falar e gravar juntos mistura a voz do aparelho no microfone.
  public func setMicArmed(_ on: Bool) {
    #if os(iOS)
      guard on else {
        setPlaybackSession()
        return
      }
      stop()
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
      try? session.setActive(true)
      // A permissão só é pedida daqui, do botão de microfone de cada treino, que
      // nasce desligado. Nenhum outro caminho encosta nisto.
      AVAudioApplication.requestRecordPermission { [weak self] granted in
        Task { @MainActor in self?.micDenied = !granted }
      }
    #endif
  }

  private func setPlaybackSession() {
    #if os(iOS)
      let session = AVAudioSession.sharedInstance()
      try? session.setCategory(.playback, mode: .spokenAudio)
      try? session.setActive(true)
    #endif
  }

  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.isSpeaking = true }
  }

  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.isSpeaking = false }
  }

  nonisolated public func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in self.isSpeaking = false }
  }

  private nonisolated static func germanVoice() -> AVSpeechSynthesisVoice? {
    if let voice = AVSpeechSynthesisVoice(language: "de-DE") { return voice }
    if let voice = AVSpeechSynthesisVoice(language: "de-AT") { return voice }
    return AVSpeechSynthesisVoice(language: "de-CH")
  }
}
