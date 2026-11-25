import Foundation

@main
struct TestDailyTask {
    static func main() throws {
        var task = DailyTask()
        task.title = "每天的任务"
        task.repeatsDaily = true
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        task.completedDays = [DailyTask.dayKey(yesterday)]
        precondition(!task.isDoneToday, "Yesterday's completion must not complete today's task")
        task.completedDays.insert(DailyTask.dayKey())
        precondition(task.isDoneToday)
        task.priority = 2
        task.notes = "备注\n第二行"
        task.category = "学习"
        let restored = try JSONDecoder().decode(DailyTask.self, from: JSONEncoder().encode(task))
        precondition(restored == task, "Task editing fields and completion history must survive relaunch")
        var oneOff = DailyTask()
        oneOff.completed = true
        precondition(oneOff.isDoneToday)
        print("PASS: daily rollover, completion, date/notes/priority/category round-trip, one-off completion")
    }
}
