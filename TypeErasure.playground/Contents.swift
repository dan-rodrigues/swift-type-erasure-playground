// TypeErasure Playground
//
// Copyright (C) 2021 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

import Foundation

/// This playground illustrates an issue that user-defined types will have when creating type-erasing wrappers such as `AnyHashable`
/// In this scenario, the problem is the the user-defined wrapper being unable to handle a `Self` constraint for certain class hierarchies
/// The motivation behind this playground is that the implementation might appear correct at a glance when in reality, it doesn't work
///
/// Similar issues may appear when mixing the generic parameter (such as `Base` in `SomeHashable.init()`) with dynamic casts (`as?`)
/// The behaviour will depend on what hte static type at the callsite of `SomeHashable.init()` is, as this defines the type will be used in the RHS of the `as?` statement below.
///
/// It is *not* meant to demonstrate any workarounds to this issue as it's fundamentally a compiler limitation that should not be hacked around
/// This playground is more of a cautionary example
///
/// Xcode 12.5.1 was used to create this playground

/// `SomeHashable` is an *approximate* reimplementation of the `AnyHashable`struct found in the Swift stdlib.
/// Note this doesn't cover all cases as `AnyHashable` and the reasons are discussed below along with why there is no compiler support to do so (as of Swift 5.0)
///
/// `AnyHashable` declaration as of 8th Jun 2021:
/// https://github.com/apple/swift/blob/23c3b15f5f2676dd2cfeaabdaf62ae9b49d6faf1/stdlib/public/core/AnyHashable.swift#L138

struct SomeHashable: Hashable {

    private let base: Any

    private let isEqual: (_ other: SomeHashable) -> Bool
    private let hashInto: (inout Hasher) -> Void

    init<Base: Hashable>(_ wrapped: Base) {
        self.base = wrapped

        self.isEqual = { other in
            /*
             * Try casting other to the *static type* Base, which will then allow us to use the == operator
             * This works for value types and flat class hierarchies but not necessarily for classes with inheritance
             * Inheritance may mean that we can't cast other.base to Base due to incompatible types, despite their compatible superclass
             *
             * Since Base is a static type and as? works with dynamic types, should probably be careful mixing the two or just avoiding it if possible
             */
            return (other.base as? Base).map { $0 == wrapped } ?? false
        }

        self.hashInto = { hasher in
            wrapped.hash(into: &hasher)
        }
    }

    static func == (lhs: SomeHashable, rhs: SomeHashable) -> Bool {
        return lhs.isEqual(rhs)
    }

    func hash(into hasher: inout Hasher) {
        hashInto(&hasher)
    }
}

/// `Super` demonstrates the issue with the above `SomeHashable` wrapper with its `Equatable` conformance (as a result of conforming to `Hashable`)
/// While `SomeHashable` works as expected when the static type `Base` is `Super`, it doesn't work as expected when subclasses of `Super` are used instead.

class Super: Hashable {

    private let value: Int

    init(_ value: Int) {
        self.value = value
    }

    static func == (lhs: Super, rhs: Super) -> Bool {
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
}

/// `SubA` and `SubB` only exist to illustrate the issue with the static types combined with the typecast in `SomeHashable`

class SubA: Super {}
class SubB: Super {}

/// Equality checking with the above class hierarchy will rely on the `Equatable` conformance provided by `Super`
/// As a baseline, let's use the `==` operator directly as provided by `Equatable`:

SubA(1) == SubB(1) // true
SubA(2) == SubB(3) // false

/// `AnyHashable` with identical values, which will match the behaviour above when using `==` directly:
/// The `AnyHashable` implementation will correctly use the `==` implementation provided by the common ancestor `Super`.

AnyHashable(SubA(1)) == AnyHashable(SubB(1)) // true
AnyHashable(SubA(2)) == AnyHashable(SubB(3)) // false

/// Now let's use the custom `SomeHashable` type with the same test case, where the wrapped values are equal
/// Note that this does not match the behaviour of `AnyHashable`. The type cast within `SomeHashable` fails because the static types are not compatible
/// There is an attempt to cast `SubA` to `SubB` which will always fail. The fact that they have a common ancestor isn't relevant.

SomeHashable(SubA(1)) == SomeHashable(SubB(1)) // false (attempted to cast SubB instance to SubA, fails)

/// This can be hacked around by coercing the generic parameter in `SomeHashable.init` to the common superclass `Super`
/// It now produces the expected result since the cast within `SomeHashable` will cast to the common superclass instead, which will succeed.
/// This is a poor workaround though for several reasons:
///
/// - It relies on the programmer's understanding of the class hierarchy rather than the type inference that is built into Swift
/// - The default generic parameters which are then used by `SomeHashable` results in the "broken" behaviour which must be manually patched at callsite
/// - It is extremely error prone as the failing case above builds and runs without any warning
/// - Different class hierarchies will require different coercions using `as` on a case-by-case basis

SomeHashable(SubA(1) as Super) == SomeHashable(SubB(1) as Super) // true (casting SubB instance to Super, succeeds)

/// `AnyHashable` circumvents this by calling a C++ upcast function. User-defined types do not have access to this sort of functionality.
/// This mimics the behaviour of using the `==` operator directly, which will resolve the the `Equatable` implementation provided by `Super`
///
/// C++ implementation of `_swift_makeAnyHashableUpcastingToHashableBaseType()`
/// https://github.com/apple/swift/blob/7123d2614b5f222d03b3762cb110d27a9dd98e24/stdlib/public/runtime/AnyHashableSupport.cpp#L147
