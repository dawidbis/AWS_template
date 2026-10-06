import app


def test_handler_echoes_event():
    result = app.handler({"hello": "world"}, None)
    assert result == {"ok": True, "received": {"hello": "world"}}
