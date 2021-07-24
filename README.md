# Swift Type-Erasure Playground

## Background

The Swift version at time of writing (5.x) has restrictions around generics regarding existentials which are covered in [this](https://github.com/apple/swift/blob/main/docs/GenericsManifesto.md#existentials) part of the GenericsManifesto. These restrictions motivate users to define their own type-erasing wrappers when the concrete type is to be hidden or when there is a need to store some conforming instance without referring to any given concrete type.

## Motivation

The mentioned type-erasing wrappers cover many cases but it's not currently possible to cover _all_ cases as demonstrated in this playground. A major problem with this as that the author can implement a wrapper that apparently works for simpler use cases without realizing this, until much later when bugs become apparent. Because these bugs are only noticed at runtime without any errors or warnings at build time, they may be difficult to debug when they do arise.

## Discussion

There are several type-erasing wrappers included in the Swift standard library such as the ones listed [here](https://developer.apple.com/documentation/swift/swift_standard_library/collections/supporting_types). The one focused on this is playground is [`AnyHashable`](https://developer.apple.com/documentation/swift/anyhashable) along with a problematic attempt to implement a user-defined equivalent, called `SomeHashable`. An edited portion of the playground is included below which summarizes the issue.

```swift
class Super: Hashable { /* includes Hashable conformance and initializer */ }

class SubA: Super {}
class SubB: Super {}

// Baseline: using the == operator directly, uses Equatable conformance included in Super
SubA(1) == SubB(1) // true
SubA(2) == SubB(3) // false

// AnyHashable: works as above
AnyHashable(SubA(1)) == AnyHashable(SubB(1)) // true
AnyHashable(SubA(2)) == AnyHashable(SubB(3)) // false

// SomeHashable: doesn't work as above for reasons detailed in the playground
SomeHashable(SubA(1)) == SomeHashable(SubB(1)) // false (attempted to cast SubB instance to SubA, fails)

// SomeHashable + type coercion hack: "works" but has many downsides, wouldn't recommend
SomeHashable(SubA(1) as Super) == SomeHashable(SubB(1) as Super) // true (casting SubB instance to Super, succeeds)
```

`AnyHashable` doesn't suffer from these issues thanks to [this supporting C++ code](https://github.com/apple/swift/blob/7123d2614b5f222d03b3762cb110d27a9dd98e24/stdlib/public/runtime/AnyHashableSupport.cpp#L147) that effectively performs the common superclass search at runtime, then calling the `==` implementation of that common superclass. The resulting behaviour is the same as using the `==` operator directly.

There is currently no way to perform this sort of dynamic upcast in pure Swift code which prevents user-defined types from doing the same as `AnyHashable`. 

Most of the commentary is in [playground source](TypeErasure.playground/Contents.swift) itself. The contents of this README is just a brief summary.

## Tools

Xcode 12.5.1 was used to create the playground.
