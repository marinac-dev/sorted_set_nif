# Benchmark comparing lock() vs try_lock() for a 100k player leaderboard
# This simulates a frequently updated game leaderboard scenario

defmodule LeaderboardBenchmark do
  @moduledoc """
  Simulates a game leaderboard with 100,000 players sorted by level.
  Tests concurrent updates that happen in real game scenarios:
  - Players leveling up
  - New players joining
  - Players leaving
  - Reading top rankings
  - Finding player positions
  """

  # Player data structure: {level, player_id}
  # We use tuples to represent players sorted by level

  def generate_players(count) do
    # Generate players with levels distributed realistically
    # Most players are low-mid level, fewer at high levels
    # Use fixed seed for reproducibility
    :rand.seed(:exsss, {1, 2, 3})

    Enum.map(1..count, fn id ->
      # Exponential distribution for more realistic level spread
      level = :rand.uniform(100) + :rand.uniform(50) * :rand.uniform(10)
      {level, id}
    end)
  end

  def create_leaderboard(players, max_bucket_size \\ 256) do
    set = Discord.SortedSet.new(length(players), max_bucket_size)

    # Batch insert for efficient initialization
    Enum.each(players, fn player ->
      Discord.SortedSet.add(set, player)
    end)

    set
  end

  def simulate_level_up(set, iteration) do
    # Simulate a player leveling up
    # Use deterministic selection based on iteration for reproducibility
    old_level = rem(iteration * 17, 500) + 1
    player_id = rem(iteration * 23, 100_000) + 1
    new_level = old_level + 1

    # Remove old level (ignore if not found) and add new level
    Discord.SortedSet.remove(set, {old_level, player_id})
    Discord.SortedSet.add(set, {new_level, player_id})

    set
  end

  def simulate_player_join(set, iteration) do
    # New player joins at level 1
    player_id = 100_000 + iteration
    Discord.SortedSet.add(set, {1, player_id})
    set
  end

  def simulate_player_leave(set, iteration) do
    # Remove a player deterministically (ignore if not found)
    level = rem(iteration * 19, 500) + 1
    player_id = rem(iteration * 29, 100_000) + 1
    Discord.SortedSet.remove(set, {level, player_id})
    set
  end

  def read_top_10(set) do
    Discord.SortedSet.slice(set, 0, 10)
  end

  def read_top_100(set) do
    Discord.SortedSet.slice(set, 0, 100)
  end

  def find_player_rank(set, iteration) do
    # Find a player's rank deterministically
    level = rem(iteration * 13, 500) + 1
    player_id = rem(iteration * 31, 100_000) + 1
    Discord.SortedSet.find_index(set, {level, player_id})
  end

  def check_leaderboard_size(set) do
    Discord.SortedSet.size(set)
  end

  def mixed_workload(set, iteration) do
    # Simulate realistic mixed workload
    case rem(iteration, 10) do
      0 -> read_top_10(set)
      1 -> read_top_100(set)
      2 -> find_player_rank(set, iteration)
      3 -> check_leaderboard_size(set)
      4 -> simulate_player_join(set, iteration)
      5 -> simulate_player_leave(set, iteration)
      _ -> simulate_level_up(set, iteration)
    end

    set
  end

  def concurrent_mixed_workload(set, num_operations) do
    # Run operations concurrently to stress test the lock mechanism
    tasks =
      for i <- 1..num_operations do
        Task.async(fn ->
          # Catch any errors including lock_fail
          try do
            result = mixed_workload(set, i)
            {:ok, result}
          rescue
            e in ArgumentError ->
              # Check if it's a lock_fail error
              if String.contains?(Exception.message(e), "lock_fail") do
                {:error, :lock_fail}
              else
                {:error, {:argument_error, Exception.message(e)}}
              end
          catch
            kind, reason ->
              {:error, {kind, reason}}
          end
        end)
      end

    results = Task.await_many(tasks, 30_000)

    # Count successes vs lock failures vs other errors
    successes =
      Enum.count(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    lock_failures =
      Enum.count(results, fn
        {:error, :lock_fail} -> true
        _ -> false
      end)

    other_errors =
      Enum.count(results, fn
        {:error, :lock_fail} -> false
        {:ok, _} -> false
        {:error, _} -> true
      end)

    %{
      total: num_operations,
      successes: successes,
      lock_failures: lock_failures,
      other_errors: other_errors,
      lock_fail_rate: lock_failures / num_operations * 100,
      total_error_rate: (lock_failures + other_errors) / num_operations * 100
    }
  end
end

IO.puts("Generating 100,000 players...")
players = LeaderboardBenchmark.generate_players(100_000)

IO.puts("Testing leaderboard creation...")
test_leaderboard = LeaderboardBenchmark.create_leaderboard(players)
initial_size = Discord.SortedSet.size(test_leaderboard)
IO.puts("✓ Leaderboard created successfully with #{initial_size} players")

# Create input data that will be used to recreate leaderboard for each scenario
input_data = {players, 256}

IO.puts("\nRunning benchmarks...\n")

# Separate read-only and write benchmarks for accurate measurement
Benchee.run(
  %{
    # Read-only operations - can share state
    "read_top_10" => fn {set, _i} -> LeaderboardBenchmark.read_top_10(set) end,
    "read_top_100" => fn {set, _i} -> LeaderboardBenchmark.read_top_100(set) end,
    "find_rank" => fn {set, i} -> LeaderboardBenchmark.find_player_rank(set, i) end,
    "check_size" => fn {set, _i} -> LeaderboardBenchmark.check_leaderboard_size(set) end
  },
  inputs: %{
    "100k_leaderboard" => input_data
  },
  before_scenario: fn {players, max_bucket_size} ->
    IO.puts("  Creating fresh leaderboard for read-only scenario...")
    leaderboard = LeaderboardBenchmark.create_leaderboard(players, max_bucket_size)
    {leaderboard, 0}
  end,
  before_each: fn {set, counter} ->
    # For read operations, just increment counter
    {set, counter + 1}
  end,
  time: 10,
  memory_time: 2,
  warmup: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Write Operations Benchmark (Fresh state per scenario)")
IO.puts(String.duplicate("=", 60) <> "\n")

Benchee.run(
  %{
    # Write operations - need fresh state per scenario to avoid compounding effects
    "level_up" => fn {set, i, _} -> LeaderboardBenchmark.simulate_level_up(set, i) end,
    "player_join" => fn {set, i, _} -> LeaderboardBenchmark.simulate_player_join(set, i) end,
    "player_leave" => fn {set, i, _} -> LeaderboardBenchmark.simulate_player_leave(set, i) end,
    "mixed_workload" => fn {set, i, _} -> LeaderboardBenchmark.mixed_workload(set, i) end
  },
  inputs: %{
    "100k_leaderboard" => input_data
  },
  before_scenario: fn {players, max_bucket_size} ->
    IO.puts("  Creating fresh leaderboard for write scenario...")
    leaderboard = LeaderboardBenchmark.create_leaderboard(players, max_bucket_size)
    size = Discord.SortedSet.size(leaderboard)
    {leaderboard, 0, size}
  end,
  before_each: fn {set, counter, initial_size} ->
    # Increment counter for deterministic operations
    {set, counter + 1, initial_size}
  end,
  after_scenario: fn {set, _counter, initial_size} ->
    # Validate that leaderboard is still functional
    final_size = Discord.SortedSet.size(set)
    IO.puts("  Scenario complete: Initial size=#{initial_size}, Final size=#{final_size}")
    :ok
  end,
  time: 10,
  memory_time: 2,
  warmup: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)

IO.puts("\n\n=== CONCURRENT WORKLOAD TEST ===\n")
IO.puts("Testing with concurrent operations to stress the lock mechanism...")

Benchee.run(
  %{
    "concurrent_10_ops" => fn {players, max_bucket_size} ->
      set = LeaderboardBenchmark.create_leaderboard(players, max_bucket_size)
      LeaderboardBenchmark.concurrent_mixed_workload(set, 10)
    end,
    "concurrent_50_ops" => fn {players, max_bucket_size} ->
      set = LeaderboardBenchmark.create_leaderboard(players, max_bucket_size)
      LeaderboardBenchmark.concurrent_mixed_workload(set, 50)
    end,
    "concurrent_100_ops" => fn {players, max_bucket_size} ->
      set = LeaderboardBenchmark.create_leaderboard(players, max_bucket_size)
      LeaderboardBenchmark.concurrent_mixed_workload(set, 100)
    end
  },
  inputs: %{
    "100k_leaderboard" => input_data
  },
  time: 10,
  memory_time: 0,
  warmup: 2,
  formatters: [
    Benchee.Formatters.Console
  ]
)

IO.puts("\n")
IO.puts("=" |> String.duplicate(60))
IO.puts("Testing lock timeout behavior with concurrent operations")
IO.puts("=" |> String.duplicate(60))

# Test with increasing concurrency to see when lock timeouts occur
# Create a fresh leaderboard for these tests
LeaderboardBenchmark.create_leaderboard(players, 256)

for num_ops <- [10, 25, 50, 100] do
  IO.puts("\nTesting with #{num_ops} concurrent operations...")
  # Create fresh leaderboard for each test
  fresh_set = LeaderboardBenchmark.create_leaderboard(players, 256)
  result = LeaderboardBenchmark.concurrent_mixed_workload(fresh_set, num_ops)

  IO.puts("  Total ops: #{result.total}")
  IO.puts("  Successes: #{result.successes}")
  IO.puts("  Lock failures: #{result.lock_failures}")
  IO.puts("  Other errors: #{result.other_errors}")
  IO.puts("  Lock fail rate: #{Float.round(result.lock_fail_rate, 2)}%")
  IO.puts("  Total error rate: #{Float.round(result.total_error_rate, 2)}%")

  cond do
    result.lock_failures > 0 ->
      IO.puts("  ⚠️  Lock contention detected - #{result.lock_failures} operations failed to acquire lock!")

    result.other_errors > 0 ->
      IO.puts("  ⚠️  Other errors detected!")

    true ->
      IO.puts("  ✓ All operations succeeded")
  end
end

IO.puts("\n✓ Benchmark complete!")
