import Foundation

public struct ExercisePrescription: Codable, Hashable, Sendable {
  public var prepSets: Int
  public var workSets: Int
  public var repsMin: Int
  public var repsMax: Int
  public var workToFailure: Bool
  public var startingWeightKg: Double

  public init(
    prepSets: Int, workSets: Int, repsMin: Int, repsMax: Int, workToFailure: Bool,
    startingWeightKg: Double
  ) {
    self.prepSets = prepSets
    self.workSets = workSets
    self.repsMin = repsMin
    self.repsMax = repsMax
    self.workToFailure = workToFailure
    self.startingWeightKg = startingWeightKg
  }

  public var repsLabel: String {
    repsMin == repsMax ? "\(repsMin)" : "\(repsMin)–\(repsMax)"
  }
}

/// A série de aquecimento. O índice é único dentro do exercício, então serve de
/// identidade estável para a lista.
public struct PrepSet: Codable, Hashable, Sendable, Identifiable {
  public var index: Int
  public var weightKg: Double
  public var reps: Int
  public var completedAt: Date?

  public var id: Int { index }
  public var isDone: Bool { completedAt != nil }
}

public struct WorkSet: Codable, Hashable, Sendable, Identifiable {
  public var index: Int
  public var weightKg: Double
  public var reps: Int
  public var toFailure: Bool
  public var completedAt: Date?

  public var id: Int { index }
  public var isDone: Bool { completedAt != nil }
}

public struct ExerciseSets: Codable, Hashable, Sendable {
  public var prep: [PrepSet]
  public var work: [WorkSet]

  public var completedWorkCount: Int { work.count(where: \.isDone) }
}

public struct PreviousWorkSets: Codable, Hashable, Sendable {
  public var date: CalendarDate
  public var weightKg: Double
  public var reps: [Int]
  public var volumeKg: Double
}

/// De onde o exercício veio: do plano ou acrescentado só para a sessão de hoje.
public enum ExerciseOrigin: String, Codable, Hashable, Sendable {
  case plano, sessao
}

public struct DashboardExercise: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var muscleGroup: String
  public var equipment: String
  public var imageUrl: String?
  public var order: Int
  public var prescription: ExercisePrescription
  public var previous: PreviousWorkSets?
  public var sets: ExerciseSets
  /// Nulos no servidor antigo, que não guarda a sobreposição da sessão.
  public var note: String?
  public var origin: ExerciseOrigin?
  /// Nulos no servidor antigo. `restSeconds` nulo é o descanso padrão.
  public var prepWeightKg: Double? = nil
  public var restSeconds: Int? = nil
  public var previousPrep: PreviousWorkSets? = nil

  public var isComplete: Bool { sets.completedWorkCount >= prescription.workSets }
  public var isFromSession: Bool { origin == .sessao }
}

/// O descanso quando nem o plano nem o aparelho escolheram outro.
public let defaultRestSeconds = 90

public struct WorkoutSummary: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var focus: String
  public var estimatedMinutes: Int
  public var exerciseCount: Int
  public var workSetCount: Int
  public var completedWorkSetCount: Int
  public var completionPercent: Int
  public var exercises: [DashboardExercise]
}

public struct WorkoutSessionTiming: Equatable, Sendable {
  public let startedAt: Date
  public let finishedAt: Date?

  /// O aquecimento continua sendo a âncora do começo, porque é o que marca a chegada na
  /// academia. Sem nenhum aquecimento feito, vale a primeira série valendo: antes disso
  /// quem ia direto ao peso ficava sem relógio nenhum.
  ///
  /// `finishedAt` é o "encerrar" tocado antes de todas as séries saírem. Ele
  /// para o relógio ali, e não na última série feita.
  public init?(_ workout: WorkoutSummary, finishedAt closed: Date? = nil) {
    let prepDates = workout.exercises.flatMap { $0.sets.prep.map(\.completedAt) }
    let workDates = workout.exercises.flatMap { $0.sets.work.map(\.completedAt) }
    guard let startedAt = prepDates.compactMap({ $0 }).min()
      ?? workDates.compactMap({ $0 }).min() else { return nil }
    let dates = prepDates + workDates
    self.startedAt = startedAt
    let allDone = dates.allSatisfy { $0 != nil } ? dates.compactMap { $0 }.max() : nil
    finishedAt = allDone ?? closed.map { max($0, startedAt) }
  }

  public func elapsed(at now: Date) -> TimeInterval {
    max(0, (finishedAt ?? now).timeIntervalSince(startedAt))
  }
}

/// O resumo que aparece ao encerrar o treino. A comparação usa só os
/// exercícios que têm sessão anterior, senão um exercício novo parece progresso.
public struct WorkoutRecap: Equatable, Sendable {
  public let durationSeconds: Int?
  public let workVolumeKg: Double
  public let doneSets: Int
  public let totalSets: Int
  /// Volume de hoje e da última vez, só dos exercícios com `previous`. Nulo
  /// quando nenhum exercício tem histórico.
  public let comparison: VolumeComparison?

  public struct VolumeComparison: Equatable, Sendable {
    public let today: Double
    public let previous: Double
  }

  public init(_ workout: WorkoutSummary, timing: WorkoutSessionTiming?, now: Date = .now) {
    durationSeconds = timing.map { Int($0.elapsed(at: now)) }
    workVolumeKg = workout.exercises.reduce(0) { $0 + HenriqueCore.workVolumeKg($1.sets.work) }
    doneSets = workout.exercises.reduce(0) { $0 + $1.sets.completedWorkCount }
    totalSets = workout.exercises.reduce(0) { $0 + $1.sets.work.count }
    let compared = workout.exercises.filter { $0.previous != nil }
    comparison = compared.isEmpty ? nil : VolumeComparison(
      today: compared.reduce(0) { $0 + HenriqueCore.workVolumeKg($1.sets.work) },
      previous: compared.reduce(0) { $0 + ($1.previous?.volumeKg ?? 0) })
  }
}

public struct ProgressPoint: Codable, Hashable, Sendable, Identifiable {
  public var date: CalendarDate
  public var estimatedOneRepMax: Double
  public var volumeKg: Double

  public var id: CalendarDate { date }
}

public struct BodyMeasurement: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var date: CalendarDate
  public var weightKg: Double
  public var bodyFatPercent: Double?
  public var waistCm: Double?
  public var chestCm: Double?
  public var armCm: Double?
  public var thighCm: Double?
}

public enum ProjectionConfidence: String, Codable, Hashable, Sendable {
  case low, medium, high
}

public struct Projection: Codable, Hashable, Sendable {
  public var metric: String
  public var current: Double
  public var target: Double
  public var weeklyChange: Double
  public var weeksRemaining: Int?
  public var confidence: ProjectionConfidence
}

public struct PlanExercise: Codable, Hashable, Sendable, Identifiable {
  public var exerciseId: String
  public var prepSets: Int
  public var workSets: Int
  public var repsMin: Int
  public var repsMax: Int
  public var workToFailure: Bool
  public var startingWeightKg: Double
  /// Nulo deixa o servidor calcular a carga do aquecimento.
  public var prepWeightKg: Double?
  /// Nulo é o descanso padrão.
  public var restSeconds: Int?
  /// O que o servidor precisa para criar o exercício quando o id ainda não
  /// existe no banco. Nulo quando o exercício já é do catálogo.
  public var name: String?
  public var muscleGroup: String?
  public var equipment: String?
  public var imageUrl: String?

  public var id: String { exerciseId }

  public init(
    exerciseId: String, prepSets: Int, workSets: Int, repsMin: Int, repsMax: Int,
    workToFailure: Bool, startingWeightKg: Double, prepWeightKg: Double? = nil,
    restSeconds: Int? = nil, name: String? = nil,
    muscleGroup: String? = nil, equipment: String? = nil, imageUrl: String? = nil
  ) {
    self.exerciseId = exerciseId
    self.prepSets = prepSets
    self.workSets = workSets
    self.repsMin = repsMin
    self.repsMax = repsMax
    self.workToFailure = workToFailure
    self.startingWeightKg = startingWeightKg
    self.prepWeightKg = prepWeightKg
    self.restSeconds = restSeconds
    self.name = name
    self.muscleGroup = muscleGroup
    self.equipment = equipment
    self.imageUrl = imageUrl
  }
}

public struct WeekPlanItem: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  /// Vazio quando o treino ainda não tem dia.
  public var weekdays: [Int]
  public var name: String
  public var focus: String
  public var exerciseCount: Int
  public var exercises: [PlanExercise]
  public var estimatedMinutes: Int
  /// Hex `#RRGGBB`. Nulo quando o treino não tem cor escolhida.
  public var color: String?

  /// O dia desse treino mais perto de `today`, andando para a frente. Hoje
  /// conta como distância zero, então quem treina hoje fica em hoje.
  public func nextWeekday(from today: Int) -> Int? {
    weekdays.min { ($0 - today + 7) % 7 < ($1 - today + 7) % 7 }
  }
}

extension WeekPlanItem {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    weekdays = try container.decode([Int].self, forKey: .weekdays)
    guard weekdays.allSatisfy({ (0...6).contains($0) }) else {
      throw DecodingError.dataCorruptedError(
        forKey: .weekdays, in: container, debugDescription: "dia da semana inválido")
    }
    name = try container.decode(String.self, forKey: .name)
    focus = try container.decode(String.self, forKey: .focus)
    exerciseCount = try container.decode(Int.self, forKey: .exerciseCount)
    exercises = try container.decode([PlanExercise].self, forKey: .exercises)
    estimatedMinutes = try container.decode(Int.self, forKey: .estimatedMinutes)
    color = try container.decodeIfPresent(String.self, forKey: .color)
  }
}

/// Um dia com ao menos uma série valendo feita. `completed` é o dia em que
/// todas as séries do treino saíram.
public struct AttendanceDay: Codable, Hashable, Sendable, Identifiable {
  public var date: CalendarDate
  public var workSets: Int
  public var completed: Bool
  /// Os treinos feitos nesse dia, na ordem em que a primeira série de cada um
  /// saiu. Vazio quando o servidor é velho e não manda o campo.
  public var workoutTemplateIds: [String]

  public var id: CalendarDate { date }

  public init(date: CalendarDate, workSets: Int, completed: Bool, workoutTemplateIds: [String] = []) {
    self.date = date
    self.workSets = workSets
    self.completed = completed
    self.workoutTemplateIds = workoutTemplateIds
  }
}

extension AttendanceDay {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    date = try container.decode(CalendarDate.self, forKey: .date)
    workSets = try container.decode(Int.self, forKey: .workSets)
    completed = try container.decode(Bool.self, forKey: .completed)
    workoutTemplateIds = try container.decodeIfPresent([String].self, forKey: .workoutTemplateIds) ?? []
  }
}

/// Os dias que um treino perde quando outro é salvo com eles.
public struct WeekdayHandoff: Hashable, Sendable {
  public var workoutName: String
  public var weekdays: [Int]
  /// Perdeu todos os dias e continua no plano sem dia.
  public var becomesUnscheduled: Bool

  public init(workoutName: String, weekdays: [Int], becomesUnscheduled: Bool) {
    self.workoutName = workoutName
    self.weekdays = weekdays
    self.becomesUnscheduled = becomesUnscheduled
  }
}

/// Quem ocupa cada dia da semana, sem contar o treino que está sendo editado.
/// O plano tem no máximo um treino por dia, então o mapa nunca perde dono.
public struct WeekdayOwners: Sendable {
  private let byWeekday: [Int: WeekPlanItem]

  public init(plan: some Sequence<WeekPlanItem>, excluding workoutId: String?) {
    var byWeekday: [Int: WeekPlanItem] = [:]
    for item in plan where item.id != workoutId {
      for day in item.weekdays { byWeekday[day] = item }
    }
    self.byWeekday = byWeekday
  }

  public subscript(weekday: Int) -> WeekPlanItem? { byWeekday[weekday] }

  /// O que salvar com `selection` tira dos outros treinos, na ordem do primeiro
  /// dia tirado de cada um.
  public func handoffs(to selection: Set<Int>) -> [WeekdayHandoff] {
    var handoffs: [(id: String, handoff: WeekdayHandoff)] = []
    for day in selection.sorted() {
      guard let owner = byWeekday[day] else { continue }
      if let index = handoffs.firstIndex(where: { $0.id == owner.id }) {
        handoffs[index].handoff.weekdays.append(day)
      } else {
        let handoff = WeekdayHandoff(
          workoutName: owner.name, weekdays: [day],
          becomesUnscheduled: Set(owner.weekdays).isSubset(of: selection))
        handoffs.append((owner.id, handoff))
      }
    }
    return handoffs.map(\.handoff)
  }
}

public struct ExerciseCatalogItem: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  public var muscleGroup: String
  public var equipment: String
  public var imageUrl: String?

  public init(id: String, name: String, muscleGroup: String, equipment: String, imageUrl: String? = nil) {
    self.id = id
    self.name = name
    self.muscleGroup = muscleGroup
    self.equipment = equipment
    self.imageUrl = imageUrl
  }

  /// De onde veio a linha, para o seletor separar o catálogo local da base
  /// pública sem precisar de outro tipo.
  public var isRemote: Bool { id.hasPrefix("wger-") }
}

public struct StrengthGoal: Codable, Hashable, Sendable {
  public var exerciseId: String
  public var exerciseName: String
  public var targetValue: Double
  public var lastSession: PreviousWorkSets?
}

public enum StreakKind: String, Codable, CaseIterable, Sendable {
  case attendance, complete
}

public struct StreakGoal: Codable, Hashable, Sendable {
  public var kind: StreakKind
  public var target: Int

  public init(kind: StreakKind, target: Int) {
    self.kind = kind
    self.target = target
  }
}

public struct WeeklyWorkoutSessions: Codable, Hashable, Sendable {
  public var workoutTemplateId: String
  public var count: Int

  public init(workoutTemplateId: String, count: Int) {
    self.workoutTemplateId = workoutTemplateId
    self.count = count
  }
}

public struct Dashboard: Codable, Hashable, Sendable {
  public var date: CalendarDate
  public var workout: WorkoutSummary?
  public var consistencyPercent: Int
  /// Sequência de treinos completos: sessões com todas as séries valendo feitas.
  public var currentStreak: Int
  /// Sequência de presença: dias com ao menos uma série valendo feita. Nulo no
  /// servidor antigo, e aí a presença cai para `currentStreak`.
  public var attendanceStreak: Int?
  public var streakGoals: [StreakGoal]?
  public var weeklyWorkoutSessions: [WeeklyWorkoutSessions]? = nil
  /// As trocas de segunda até seis dias depois de `date`. Nulo no servidor que
  /// ainda não troca dia, e aí o menu de troca não aparece.
  public var daySwaps: [DaySwap]? = nil
  public var weeklyCompleted: Int
  public var weeklyPlanned: Int
  public var weekPlan: [WeekPlanItem]
  /// Os dias com sessão concluída nas últimas quatro semanas. Nulo quando o
  /// servidor é velho demais para mandar o campo, e aí é "não sei", diferente da
  /// lista vazia, que é "nenhum treino".
  public var sessionDates: [CalendarDate]?
  public var exerciseCatalog: [ExerciseCatalogItem]
  public var strengthGoal: StrengthGoal?
  public var progress: [ProgressPoint]
  public var measurements: [BodyMeasurement]
  public var projection: Projection?
  /// Nulos no servidor antigo. O mapa muscular e o cartão de volume somem em vez
  /// de mostrar zero, que leria como "você não treinou".
  public var muscleLoad: [MuscleLoad]?
  public var volume: VolumeSummary?
  public var records: [PersonalRecord]?
  public var onboardingCompleted: Bool
}

extension Dashboard {
  /// A carga de trabalho é uma propriedade do exercício no plano, não de um
  /// treino específico. A API devolve o plano inteiro, então esta regra
  /// mantém todos os treinos do usuário alinhados enquanto uma resposta chega.
  public func applyingSharedExerciseWeight(_ weightKg: Double, exerciseId: String) -> Dashboard {
    var copy = self
    for planIndex in copy.weekPlan.indices {
      for exerciseIndex in copy.weekPlan[planIndex].exercises.indices
      where copy.weekPlan[planIndex].exercises[exerciseIndex].exerciseId == exerciseId {
        copy.weekPlan[planIndex].exercises[exerciseIndex].startingWeightKg = weightKg
      }
    }
    if var workout = copy.workout,
      let exerciseIndex = workout.exercises.firstIndex(where: { $0.id == exerciseId }) {
      workout.exercises[exerciseIndex].prescription.startingWeightKg = weightKg
      copy.workout = workout
    }
    return copy
  }

  public var highlightedWorkoutIDs: Set<String> {
    let sessions = weeklyWorkoutSessions ?? []
    let maximum = sessions.map(\.count).max() ?? 0
    var highlighted = Set(sessions.filter { maximum > 0 && $0.count == maximum }
      .map(\.workoutTemplateId))
    if let workout, workout.completedWorkSetCount > 0,
      workout.completedWorkSetCount < workout.workSetCount {
      highlighted.insert(workout.id)
    }
    return highlighted
  }

  public func streak(_ kind: StreakKind) -> Int {
    switch kind {
    case .attendance: attendanceStreak ?? currentStreak
    case .complete: currentStreak
    }
  }

  public func goal(_ kind: StreakKind) -> StreakGoal? {
    streakGoals?.first { $0.kind == kind }
  }

  /// `sessionDates` só lista dias já fechados, então a série marcada agora no
  /// treino de hoje conta pelo próprio painel.
  public func hasAttended(on today: CalendarDate) -> Bool {
    if sessionDates?.contains(today) == true { return true }
    return date == today && (workout?.completedWorkSetCount ?? 0) > 0
  }
}

/// A fórmula de Epley, a mesma que o servidor usa para o gráfico de força.
public func estimateOneRepMax(weightKg: Double, reps: Int) -> Double {
  guard weightKg > 0, reps > 0 else { return 0 }
  if reps == 1 { return weightKg }
  return weightKg * (1 + Double(reps) / 30)
}

/// Só séries valendo. O aquecimento sai do chão também, mas somado ele faz o
/// dia de aquecimento longo parecer treino mais forte.
public func workVolumeKg(_ work: [WorkSet]) -> Double {
  work.reduce(0) { $0 + ($1.isDone ? $1.weightKg * Double($1.reps) : 0) }
}
