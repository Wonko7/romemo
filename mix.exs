defmodule Romemo.Mixfile do
  use Mix.Project

  def project do
    [
      app: :romemo,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      applications: [:romeo],
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      #{:romeo, "~> 0.7"}
      {:romeo, github: "scrogson/romeo"}
    ]
  end
end
