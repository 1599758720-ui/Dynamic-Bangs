import Foundation
@main struct TestMusicSwipe {
 static func main() {
  var gesture = MusicSwipeRecognizer()
  precondition(gesture.consume(dx: -10, dy: 1, time: 1, precise: true, began: true) == nil)
  precondition(gesture.consume(dx: -25, dy: 1, time: 1.02, precise: true) == .next)
  precondition(gesture.consume(dx: -100, dy: 0, time: 1.04, precise: true) == nil)
  precondition(gesture.consume(dx: -100, dy: 0, time: 1.08, precise: true, momentum: true) == nil)
  precondition(gesture.consume(dx: 40, dy: 0, time: 1.8, precise: true, began: true) == .previous)
  var vertical = MusicSwipeRecognizer()
  precondition(vertical.consume(dx: 34, dy: 100, time: 1, precise: true, began: true) == nil)
  precondition(vertical.consume(dx: 1, dy: 100, time: 1.1, precise: true, ended: true) == nil)
  precondition(vertical.consume(dx: 1, dy: 1, time: 2, precise: true, began: true) == nil)
  var mouse = MusicSwipeRecognizer()
  precondition(mouse.consume(dx: -10, dy: 0, time: 1, precise: false) == .next)
  precondition(mouse.consume(dx: -10, dy: 0, time: 1.1, precise: false) == nil)
  precondition(mouse.consume(dx: 10, dy: 0, time: 2, precise: false) == .previous)
  precondition(mouse.consume(dx: .nan, dy: 0, time: 3, precise: true) == nil)
  print("PASS: deliberate swipe, threshold, vertical rejection, one command per gesture, momentum, cooldown, mouse, invalid input")
 }
}
