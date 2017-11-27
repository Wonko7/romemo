defmodule RomemoTest do
  use ExUnit.Case
  doctest Romemo

  test "greets the world" do
    assert Romemo.hello() == :world
  end
end
