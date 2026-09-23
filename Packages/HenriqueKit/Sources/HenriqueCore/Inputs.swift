import Foundation

/// A série gravada. O aquecimento não tem falha e a série de trabalho sempre
/// tem, então o enum impede de montar a combinação que o servidor recusaria.
public enum RecordSetInput: Hashable, Sendable, Encodable {
  case prep(Fields)
  case work(Fields, toFailure: Bool)

  public struct Fields: Hashable, Sendable, Encodable {
    public var date: CalendarDate
    public var workoutTemplateId: String
    public var exerciseId: String
    public var setIndex: Int
    public var weightKg: Double
    public var reps: Int
    public var completed: Bool

    public init(
      date: CalendarDate, workoutTemplateId: String, exerciseId: String, setIndex: Int,
      weightKg: Double, reps: Int, completed: Bool
    ) {
      self.date = date
      self.workoutTemplateId = workoutTemplateId
      self.exerciseId = exerciseId
      self.setIndex = setIndex.clamped(to: Limits.setIndex)
      self.weightKg = weightKg.clamped(to: Limits.setWeightKg)
      self.reps = reps.clamped(to: Limits.reps)
      self.completed = completed
    }
  }

  private enum CodingKeys: String, CodingKey {
    case kind, date, workoutTemplateId, exerciseId, setIndex, weightKg, reps, completed, toFailure
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    let fields: Fields
    switch self {
    case .prep(let value):
      fields = value
      try container.encode("prep", forKey: .kind)
    case .work(let value, let toFailure):
      fields = value
      try container.encode("work", forKey: .kind)
      try container.encode(toFailure, forKey: .toFailure)
    }
    try container.encode(fields.date, forKey: .date)
    try container.encode(fields.workoutTemplateId, forKey: .workoutTemplateId)
    try container.encode(fields.exerciseId, forKey: .exerciseId)
    try container.encode(fields.setIndex, forKey: .setIndex)
    try container.encode(fields.weightKg, forKey: .weightKg)
    try container.encode(fields.reps, forKey: .reps)
    try container.encode(fields.completed, forKey: .completed)
  }
}

public struct AddMeasurementInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var weightKg: Double
  public var bodyFatPercent: Double?
  public var waistCm: Double?
  public var chestCm: Double?
  public var armCm: Double?
  public var thighCm: Double?

  public init(
    date: CalendarDate, weightKg: Double, bodyFatPercent: Double? = nil, waistCm: Double? = nil,
    chestCm: Double? = nil, armCm: Double? = nil, thighCm: Double? = nil
  ) {
    self.date = date
    self.weightKg = weightKg.clamped(to: Limits.bodyWeightKg)
    self.bodyFatPercent = bodyFatPercent?.clamped(to: Limits.bodyFatPercent)
    self.waistCm = waistCm?.clamped(to: Limits.waistCm)
    self.chestCm = chestCm?.clamped(to: Limits.chestCm)
    self.armCm = armCm?.clamped(to: Limits.armCm)
    self.thighCm = thighCm?.clamped(to: Limits.thighCm)
  }
}

public struct SaveWorkoutInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  /// Nulo cria um treino novo. Com id, atualiza esse treino.
  public var workoutTemplateId: String?
  /// Os dias que passam a ser desse treino. Outro treino que tinha algum deles
  /// perde só esses dias.
  public var weekdays: [Int]
  public var name: String
  public var focus: String
  public var estimatedMinutes: Int
  /// Hex `#RRGGBB`. Nulo some do corpo e o servidor mantém a cor que já tinha.
  public var color: String?
  public var exercises: [PlanExercise]

  public init(
    date: CalendarDate, workoutTemplateId: String?, weekdays: [Int], name: String, focus: String,
    estimatedMinutes: Int, color: String? = nil, exercises: [PlanExercise]
  ) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
    self.weekdays = weekdays
    self.name = name.trimmingCharacters(in: .whitespaces).cut(to: Limits.workoutNameLength)
    self.focus = focus.trimmingCharacters(in: .whitespaces).cut(to: Limits.workoutFocusLength)
    self.estimatedMinutes = estimatedMinutes.clamped(to: Limits.estimatedMinutes)
    self.color = color
    self.exercises = exercises.map(\.withinLimits)
  }
}

extension PlanExercise {
  /// O mesmo exercício com cada campo dentro da faixa do servidor. O topo das
  /// repetições sobe até a base quando ficou abaixo dela, porque o servidor
  /// recusa a faixa invertida.
  fileprivate var withinLimits: PlanExercise {
    var copy = self
    copy.exerciseId = exerciseId.cut(to: Limits.exerciseIdLength)
    copy.prepSets = prepSets.clamped(to: Limits.prepSets)
    copy.workSets = workSets.clamped(to: Limits.workSets)
    copy.repsMin = repsMin.clamped(to: Limits.planReps)
    copy.repsMax = max(repsMax.clamped(to: Limits.planReps), copy.repsMin)
    copy.startingWeightKg = startingWeightKg.clamped(to: Limits.startingWeightKg)
    copy.name = name?.cut(to: Limits.exerciseNameLength)
    copy.muscleGroup = muscleGroup?.cut(to: Limits.muscleGroupLength)
    copy.equipment = equipment?.cut(to: Limits.equipmentLength)
    copy.imageUrl = imageUrl?.cut(to: Limits.imageUrlLength)
    return copy
  }
}

public struct AttendanceRangeInput: Hashable, Sendable, Encodable {
  public var from: CalendarDate
  public var to: CalendarDate

  public init(from: CalendarDate, to: CalendarDate) {
    self.from = from
    self.to = to
  }
}

public struct SetStrengthGoalInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var exerciseId: String
  public var targetValue: Double

  public init(date: CalendarDate, exerciseId: String, targetValue: Double) {
    self.date = date
    self.exerciseId = exerciseId
    self.targetValue = targetValue.clamped(to: Limits.strengthTarget)
  }
}

public struct SetStreakGoalInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var kind: StreakKind
  public var target: Int

  public init(date: CalendarDate, kind: StreakKind, target: Int) {
    self.date = date
    self.kind = kind
    self.target = target.clamped(to: Limits.streakTarget)
  }
}

public struct DateInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public init(date: CalendarDate) { self.date = date }
}

public struct DeleteWorkoutInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var workoutTemplateId: String

  public init(date: CalendarDate, workoutTemplateId: String) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
  }
}

public struct SwapDayInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  /// Nulo volta a data para o plano. O encoder omite a chave, e o servidor lê a
  /// ausência como nulo.
  public var workoutTemplateId: String?

  public init(date: CalendarDate, workoutTemplateId: String?) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
  }
}

/// O tipo de série na sobreposição da sessão. O nome do caso é o que vai no
/// corpo, igual ao `kind` do record-set.
public enum SetKind: String, Hashable, Sendable, Codable {
  case prep, work
}

public struct SetCountInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var workoutTemplateId: String
  public var exerciseId: String
  public var kind: SetKind
  public var count: Int

  public init(date: CalendarDate, workoutTemplateId: String, exerciseId: String, kind: SetKind, count: Int) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
    self.exerciseId = exerciseId
    self.kind = kind
    self.count = count.clamped(to: kind == .prep ? Limits.prepSets : Limits.workSets)
  }
}

public struct AddSessionExerciseInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var workoutTemplateId: String
  public var exerciseId: String
  /// Nulos deixam o servidor escolher a contagem padrão.
  public var prepSets: Int?
  public var workSets: Int?

  public init(
    date: CalendarDate, workoutTemplateId: String, exerciseId: String, prepSets: Int? = nil,
    workSets: Int? = nil
  ) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
    self.exerciseId = exerciseId
    self.prepSets = prepSets?.clamped(to: Limits.prepSets)
    self.workSets = workSets?.clamped(to: Limits.workSets)
  }
}

public struct RemoveSessionExerciseInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var workoutTemplateId: String
  public var exerciseId: String

  public init(date: CalendarDate, workoutTemplateId: String, exerciseId: String) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
    self.exerciseId = exerciseId
  }
}

public struct SetExerciseNoteInput: Hashable, Sendable, Encodable {
  public var date: CalendarDate
  public var workoutTemplateId: String
  public var exerciseId: String
  /// Nulo apaga a anotação. O servidor faz o mesmo com o texto vazio, então o
  /// `init` já manda nulo e a tela não precisa distinguir os dois.
  public var note: String?

  public init(date: CalendarDate, workoutTemplateId: String, exerciseId: String, note: String?) {
    self.date = date
    self.workoutTemplateId = workoutTemplateId
    self.exerciseId = exerciseId
    let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.note = trimmed.isEmpty ? nil : trimmed.cut(to: Limits.exerciseNoteLength)
  }

  private enum CodingKeys: String, CodingKey { case date, workoutTemplateId, exerciseId, note }

  /// O nulo tem de ir no corpo, porque a chave ausente e a chave nula são coisas
  /// diferentes para quem apaga a anotação.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(date, forKey: .date)
    try container.encode(workoutTemplateId, forKey: .workoutTemplateId)
    try container.encode(exerciseId, forKey: .exerciseId)
    try container.encode(note, forKey: .note)
  }
}
