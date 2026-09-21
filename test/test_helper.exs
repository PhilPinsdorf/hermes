ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Hermes.Repo, :manual)

# Calls are driven against a mocked Asterisk (see Hermes.Ari.Client).
Mox.defmock(Hermes.Ari.ClientMock, for: Hermes.Ari.Client)
