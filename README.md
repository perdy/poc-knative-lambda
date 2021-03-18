# PoC Knative Lambda

A Proof of Concept of a lambda function based on [Knative].

This PoC is implemented using [Flama] as the framework to build the base application. The application will define an 
endpoint that will be called by Knative mechanisms and will receive an event that follows the [CloudEvents] standard.

## Quick Start
1. Build the docker image:
```commandline
python make build
```
*It could ask for installing some dependencies, such as Clinner and Jinja2, if you aceept it will install them and once 
all requirements are installed you can run the script.*

2. Run the application:
```commandline
python make run
```

### Requirements

* [Python] 3.6+

[Python]: https://www.python.org
[Flama]: https://github.com/perdy/flama/
[Knative]: https://knative.dev/
[CloudEvents]: https://cloudevents.io/