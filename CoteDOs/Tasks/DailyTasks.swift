import AppKit
import Combine
import SwiftUI

struct DailyTask: Codable, Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var notes = ""
    var date = Date()
    var priority = 1
    var category = ""
    var repeatsDaily = false
    var completed = false
    var completedDays: Set<String> = []
    var archived = false

    static func dayKey(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var isDoneToday: Bool { repeatsDaily ? completedDays.contains(Self.dayKey()) : completed }
}

final class DailyTasks: ObservableObject {
    static let shared = DailyTasks()
    @Published private(set) var tasks: [DailyTask]
    private var dayObserver: NSObjectProtocol?

    init() {
        tasks = Persistence.load([DailyTask].self, from: "daily-tasks.json") ?? []
        dayObserver = NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged,
            object: nil, queue: .main) { [weak self] _ in self?.objectWillChange.send() }
    }
    deinit { if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) } }

    var today: [DailyTask] {
        let start = Calendar.current.startOfDay(for: Date())
        return tasks.filter {
            !$0.archived && ($0.repeatsDaily || Calendar.current.isDateInToday($0.date)
                || ($0.date < start && !$0.completed))
        }.sorted {
            if $0.isDoneToday != $1.isDoneToday { return !$0.isDoneToday }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.date < $1.date
        }
    }

    func save(_ task: DailyTask) {
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.title.isEmpty else { return }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) { tasks[index] = task }
        else { tasks.append(task) }
        persist()
    }
    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if tasks[index].repeatsDaily {
            let key = DailyTask.dayKey()
            if tasks[index].completedDays.contains(key) { tasks[index].completedDays.remove(key) }
            else { tasks[index].completedDays.insert(key) }
        } else { tasks[index].completed.toggle() }
        persist()
    }
    func archive(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].archived = true
        persist()
    }
    private func persist() { Persistence.save(tasks, to: "daily-tasks.json") }
}

final class DailyTasksWindow {
    static let shared = DailyTasksWindow()
    private var window: NSWindow?
    private var editor: NSWindow?

    func show() {
        if window == nil {
            let view = DailyTasksList(store: .shared)
            window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window?.title = "每日任务"
            window?.setContentSize(NSSize(width: 540, height: 430))
            window?.isReleasedWhenClosed = false
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func edit(_ task: DailyTask = DailyTask()) {
        editor?.close()
        let view = DailyTaskEditor(draft: task) { [weak self] in self?.editor?.close() }
        editor = NSWindow(contentViewController: NSHostingController(rootView: view))
        editor?.title = task.title.isEmpty ? "添加任务" : "编辑任务"
        editor?.setContentSize(NSSize(width: 440, height: 470))
        editor?.isReleasedWhenClosed = false
        editor?.center()
        NSApp.activate(ignoringOtherApps: true)
        editor?.makeKeyAndOrderFront(nil)
    }
}

struct DailyTasksList: View {
    @ObservedObject var store: DailyTasks
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("每日任务").font(.title2.bold())
                Spacer()
                Button("添加任务", systemImage: "plus") { DailyTasksWindow.shared.edit() }.buttonStyle(.borderedProminent).tint(.mint)
            }
            List {
                ForEach(store.tasks.filter { !$0.archived }) { task in
                    HStack {
                        Button { store.toggle(task.id) } label: {
                            Image(systemName: task.isDoneToday ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.plain).font(.system(size: 17)).foregroundStyle(task.isDoneToday ? .mint : .secondary)
                            .accessibilityLabel((task.isDoneToday ? "取消完成：" : "完成任务：") + task.title)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(task.isDoneToday)
                            Text((task.repeatsDaily ? "每天重复" : task.date.formatted(date: .abbreviated, time: .omitted)) + (task.category.isEmpty ? "" : " · " + task.category))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") { DailyTasksWindow.shared.edit(task) }.buttonStyle(.borderless).tint(.mint)
                        Button("归档") { store.archive(task.id) }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { DailyTasksWindow.shared.edit(task) }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .overlay {
                if store.tasks.allSatisfy({ $0.archived }) {
                    ContentUnavailableView("给今天留一件小事", systemImage: "checklist", description: Text("点击“添加任务”，记下日期、分类或备注。"))
                }
            }
            Text("点击编辑可调整详情。每日重复任务会在新的一天重新待办。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22)
    }
}

struct DailyTaskEditor: View {
    @State private var draft: DailyTask
    let onClose: () -> Void
    init(draft: DailyTask, onClose: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onClose = onClose
    }
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("任务") {
                    TextField("名称", text: $draft.title, prompt: Text("要完成什么？"))
                        .accessibilityLabel("任务名称")
                    DatePicker("日期", selection: $draft.date, displayedComponents: .date)
                    Toggle("每天重复", isOn: $draft.repeatsDaily)
                }
                Section("安排") {
                    Picker("重要程度", selection: $draft.priority) {
                        Text("普通").tag(0); Text("重要").tag(1); Text("紧急").tag(2)
                    }.pickerStyle(.segmented)
                    TextField("分类", text: $draft.category, prompt: Text("可选"))
                }
                Section("备注") {
                    TextEditor(text: $draft.notes).font(.system(size: 12))
                        .frame(minHeight: 90).accessibilityLabel("任务备注")
                }
            }.formStyle(.grouped)
            HStack {
                Text("保存在这台 Mac 上").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("保存任务") { DailyTasks.shared.save(draft); onClose() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.mint)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(16)
        }
    }
}
