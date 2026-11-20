import QtQuick
import QtTest
import "../js/Eq.js" as Eq

TestCase {
  name: "Eq"

  function test_count_and_range() {
    compare(Eq.count, 36)
    for (var i = 0; i < Eq.count; i++)
      for (var t = 0; t < 4; t += 0.37) {
        var s = Eq.scale(i, t)
        verify(s > 0 && s <= 1, "bar " + i + " at " + t + " = " + s)
      }
  }

  function test_moves_over_time() {
    var moved = 0
    for (var i = 0; i < Eq.count; i++)
      if (Math.abs(Eq.scale(i, 0.1) - Eq.scale(i, 0.5)) > 0.01) moved++
    verify(moved > 20, "most bars move: " + moved)
  }

  function test_rest_is_flat_and_deterministic() {
    compare(Eq.scale(5, 1.23), Eq.scale(5, 1.23))
    compare(Eq.rest(5), Eq.rest(5))
    verify(Eq.rest(5) > 0 && Eq.rest(5) < 1)
  }
}
