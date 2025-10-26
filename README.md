# Discord.SortedSet

[![Hex.pm Version](http://img.shields.io/hexpm/v/sorted_set_nif.svg?style=flat)](https://hex.pm/packages/sorted_set_nif)

SortedSet is a fast and efficient data structure that provides certain guarantees and
functionality.  The core data structure and algorithms are implemented in a Native Implemented
Function in the Rust Programming Language, using the [Rustler crate](https://github.com/hansihe/rustler).

## Installation

Add SortedSet to your dependencies and then install with `mix do deps.get, deps.compile`

```elixir
def deps do
  [
    {:sorted_set_nif, "~> 1.0.0"}
  ]
end
```

## Implementation Details

Internally the Elixir terms stored in the SortedSet are converted to Rust equivalents and
stored in a Vector of Vectors.  The structure is similar to a skip-list, almost every operation
on the SortedSet will perform a linear scan through the buckets to find the bucket that owns the
term, then a binary search is done within the bucket to complete the operation.

Why not just a Vector of Terms?  This approach was explored but when the Vector needs to grow
beyond it's capacity, copying Terms over to the new larger Vector proved to be a performance
bottle neck.  Using a Vector of Vectors, the Bucket pointers can be quickly copied when
additional capacity is required.

This strategy provides a reasonable trade off between performance and implementation complexity.

When using a SortedSet, the caller can tune bucket sizes to their use case.  A default bucket
size of 500 was chosen as it provides good performance for most use cases.  See `new/2` for
details on how to provide custom tuning details.

## Guarantees

1.  Terms in the SortedSet will be sorted based on the Elixir sorting rules.
2.  SortedSet is a Set, any item can appear 0 or 1 times in the Set.

## Functionality

There is some special functionality that SortedSet provides beyond sorted and uniqueness
guarantees.

1.  SortedSet has a defined ordering, unlike a pure mathematical set.
2.  SortedSet can report the index of adding and removing items from the Set due to it's defined
    ordering property.
3.  SortedSet can provide random access of items and slices due to it's defined ordering
    property.

## Caveats

1.  Due to SortedSet's implementation, some operations that are constant time in sets have
    different performance characteristic in SortedSet, these are noted on the operations.
2.  SortedSets do not support some types of Elixir Terms, namely `reference`, `pid`, `port`,
    `function`, and `float`.  Attempting to store any of these types (or an allowed composite
    type containing one of the disallowed types) will result in an error, namely,
    `{:error, :unsupported_type}`

## Documentation

Documentation is [hosted on hexdocs](https://hexdocs.pm/sorted_set_nif).

For a local copy of the documentation, the `mix.exs` file is already set up for  generating 
documentation, simply run the following commands to generate the documentation from source.

```bash
$ mix deps.get
$ mix docs
```

## Running the Tests

There are two test suites available in this library, an ExUnit test suite that tests the 
correctness of the implementation from a black box point of view.  These tests can be run by 
running `mix test` in the root of the library.

The rust code also contains tests, these can be run by running `cargo test` in the 
`native/sorted_set_nif` directory.

## Running the Benchmarks

Before running any benchmarks it's important to remember that during development the NIF will be 
built unoptimized.  Make sure to rebuild an optimized version of the NIF before running the 
benchmarks.

There are benchmarks available in the `bench` folder, these are written with 
[Benchee](https://github.com/PragTob/benchee) and can be run with the following command.

```bash
$ OPTIMIZE_NIF=true mix run bench/{benchmark}.exs
```

Adding the `OPTIMIZE_NIF=true` will force the benchmark to run against the fully optimized NIF.

## Basic Usage

SortedSet lives in the `Discord` namespace to prevent symbol collision, it can be used directly 

```elixir
defmodule ExampleModule do
  def get_example_sorted_set() do
    Discord.SortedSet.new()
    |> Discord.SortedSet.add(1)
    |> Discord.SortedSet.add(:atom),
    |> Discord.SortedSet.add("hi there!")
  end
end
```

You can always add an `alias` to make this code less verbose

```elixir
defmodule ExampleModule do
  alias Discord.SortedSet
  
  def get_example_sorted_set() do
    SortedSet.new()
    |> SortedSet.add(1)
    |> SortedSet.add(:atom),
    |> SortedSet.add("hi there!")
  end
end
```

## Common Use Cases

### Maintaining a Sorted Leaderboard

```elixir
alias Discord.SortedSet

# Create a leaderboard with custom bucket size
leaderboard = SortedSet.new(1000, 250)

# Add scores and get their positions
{position, leaderboard} = SortedSet.index_add(leaderboard, {:score, 1500, "player1"})
# position might be 0 if this is the first/lowest score

# Get top 10 players
top_10 = SortedSet.slice(leaderboard, 0, 10)

# Find a specific player's rank
rank = SortedSet.find_index(leaderboard, {:score, 1500, "player1"})

# Get the player at rank 5
player = SortedSet.at(leaderboard, 5)
```

### Tracking Changes with Index Information

```elixir
# When adding an item, know where it was inserted
{index, set} = SortedSet.index_add(set, "banana")
# Now you can notify: "Item inserted at position #{index}"

# When removing an item, know where it was
{index, set} = SortedSet.index_remove(set, "banana")
# Now you can notify: "Item removed from position #{index}"
```

### Bulk Construction for Better Performance

```elixir
# If you have a large pre-sorted, deduplicated list
items = [1, 2, 3, 4, 5]  # already sorted and unique
set = SortedSet.from_proper_enumerable(items)

# If your list might have duplicates or isn't sorted
mixed_items = [5, 2, 3, 2, 1, 4]
set = SortedSet.from_enumerable(mixed_items)
# Much faster than adding one-by-one
```

### Working with Slices and Random Access

```elixir
# Get a page of results (pagination)
page_size = 20
page_number = 2
items = SortedSet.slice(set, page_number * page_size, page_size)

# Get a specific item by position
middle_item = SortedSet.at(set, div(SortedSet.size(set), 2))

# Safe access with default
item = SortedSet.at(set, 1000, :not_found)  # returns :not_found if out of bounds
```

## Complete API Overview

| Function | Description | Performance |
|----------|-------------|-------------|
| `new/2` | Create empty set | O(1) |
| `from_enumerable/2` | Create from any list | O(N log N) |
| `from_proper_enumerable/2` | Create from sorted, deduped list | O(N) |
| `add/2` | Add item | O(log N) |
| `index_add/2` | Add item, return index | O(log N) |
| `remove/2` | Remove item | O(log N) |
| `index_remove/2` | Remove item, return index | O(log N) |
| `size/1` | Get size | O(1) |
| `at/3` | Get item at index | O(log N) |
| `slice/3` | Get range of items | O(log N + K) where K is slice size |
| `find_index/2` | Find item's index | O(log N) |
| `to_list/1` | Convert to list | O(N) |

## Performance Tuning

The `bucket_size` parameter can be tuned for your use case:

- **Smaller buckets (100-250)**: Better for sets that are frequently modified
- **Default bucket (500)**: Good balance for most use cases  
- **Larger buckets (1000+)**: Better for large, mostly static sets

```elixir
# For frequently updated sets
active_set = SortedSet.new(1000, 250)

# For large, rarely modified sets
archive_set = SortedSet.new(10000, 1000)
```

## Advanced Usage Patterns

### Efficient Batch Operations

```elixir
# When you have a large dataset, use bulk construction
large_dataset = Enum.to_list(1..10000)
sorted_set = SortedSet.from_enumerable(large_dataset)

# Much more efficient than:
sorted_set = Enum.reduce(large_dataset, SortedSet.new(), &SortedSet.add(&2, &1))
```

### Memory-Efficient Iteration

```elixir
# Instead of converting to list (expensive), use slices for iteration
defmodule Pagination do
  def paginate(set, page_size) do
    total_size = SortedSet.size(set)
    total_pages = div(total_size + page_size - 1, page_size)
    
    for page <- 0..(total_pages - 1) do
      start_index = page * page_size
      SortedSet.slice(set, start_index, page_size)
    end
  end
end
```

### Index-Based Operations for Real-Time Updates

```elixir
defmodule LiveLeaderboard do
  def update_score(leaderboard, player, new_score) do
    old_entry = {player, _old_score}
    new_entry = {player, new_score}
    
    # Remove old score and get its position
    {old_index, leaderboard} = SortedSet.index_remove(leaderboard, old_entry)
    
    # Add new score and get its position  
    {new_index, leaderboard} = SortedSet.index_add(leaderboard, new_entry)
    
    # Notify about position change
    if old_index != new_index do
      notify_position_change(player, old_index, new_index)
    end
    
    leaderboard
  end
  
  defp notify_position_change(player, old_pos, new_pos) do
    IO.puts("#{player} moved from position #{old_pos} to #{new_pos}")
  end
end
```

Full API Documentation is available, there is also a full test suite with examples of how the 
library can be used.