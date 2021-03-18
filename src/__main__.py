#!/usr/bin/env python3
"""Run script.
"""
import typing

import uvicorn
from cloudevents.http import from_http
from flama import Flama
from flama.components import Component
from flama.http import Request

Event = typing.NewType("Event", dict)


class EventComponent(Component):
    async def resolve(self, request: Request) -> Event:
        return from_http(data=await request.body(), headers=request.headers)


app = Flama(components=[EventComponent()], schema=None, docs=None)


@app.route("/", methods=["POST"])
def lambda_function(event: Event):
    print(f"Found event: {event}.")


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port="8000")
