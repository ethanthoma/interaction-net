# Interaction Nets in Odin

This is simply a hobby project to learn Odinlang and interaction nets.

Check [docs](./docs/) for list of things planned.

The grammar is based on [HVM](https://github.com/HigherOrderCO/HVM) and their 
[paper](https://higherorderco.com/)

## Running

If you use nix and want to run an example, you can run
```
nix run github:ethanthoma/interaction-net example <example-name>
```
This will run one of the examples in [examples](./examples/) and print out its 
contents.

If you want to run your own file, you can simply run

```
nix run github:ethanthoma/interaction-net run <filename>
```

Read the [grammar](./grammar.ebnf) to make your own or simply copy an example.

## Resources
- https://arxiv.org/pdf/1505.07164
- https://github.com/cicada-lang/inet
- https://wiki.xxiivv.com/site/interaction_nets.html
- https://github.com/VictorTaelin/Interaction-Calculus
- https://zicklag.katharos.group/blog/interaction-nets-combinators-calculus/
- https://en.wikipedia.org/wiki/Interaction_nets
