def test_ai_intelligence
  # 1. 明显的 Nil 崩溃风险
  user = nil
  puts user.name if 1 == 1

  # 2. 严重的资源泄露（只开不关）
  f = File.open("test.txt", "w")
  f.write("leak")
  # 故意不写 f.close

  # 3. 极其低效的循环
  (1..100).each { |i| (1..100).each { |j| puts i + j } }
end