//
//  ContentView.swift
//  ArchiTemplate
//
//  Created by Admin on 23/10/2021.
//

import Combine
import SwiftUI

// MARK: Service

class MockService {
    func fetch<Output>(_ value: Output, in delay: ClosedRange<Double> = 0.5 ... 3) -> AnyPublisher<Output, Error> {
        let publisher = PassthroughSubject<Output, Error>()
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: delay)) {
            guard Int.random(in: 1 ... 100) != 1 else {
                return publisher.send(completion: .failure(URLError(.badServerResponse)))
            }
            publisher.send(value)
            publisher.send(completion: .finished)
        }
        return publisher.eraseToAnyPublisher()
    }
}

// MARK: Model

struct Item: Identifiable {
    let id = UUID()
    var name: String
    var score: Int?
    var date: Date?
}

extension Array where Element == Item {
    func updateItem(id: Item.ID, score: Int?? = nil, date: Date?? = nil) -> Self {
        guard let index = firstIndex(where: { $0.id == id }) else { return self }
        var result = self
        if let score = score {
            result[index].score = score
        }
        if let date = date {
            result[index].date = date
        }
        return result
    }
}

// MARK: Provider

class ItemProvider {
    let service = MockService()
    func fetchScore() -> AnyPublisher<Int, Error> {
        service.fetch(Int.random(in: 1 ... 100), in: 0...4)
            .eraseToAnyPublisher()
    }

    func fetchDate() -> AnyPublisher<Date, Error> {
        service.fetch(Date(timeIntervalSinceNow: Double.random(in: 10000 ... 100000)))
            .eraseToAnyPublisher()
    }
}

// MARK: Store

protocol WithMachine {
    associatedtype State
    associatedtype Input
    associatedtype Action
    associatedtype SideEffect

    var action: PassthroughSubject<Action?, Never> { get }
    var sideEffects: PassthroughSubject<[SideEffect], Never> { get }
    func send(_ input: Input) -> Void
    func reducer(currentState: State, action: Action?) -> State
    func resolveSideEffect(_ sideEffect: SideEffect) -> AnyPublisher<Action, Error>
}

extension WithMachine {
    func setup(initialValue: State,
               bag: inout Set<AnyCancellable>
    ) -> AnyPublisher<(State, Int, [String]), Never> {
        let state = CurrentValueSubject<State, Never>(initialValue)
        let currentSideEffects = CurrentValueSubject<[(UUID, SideEffect)], Never>([])
        let errors = CurrentValueSubject<[String], Never>([])
        let feedbacks = PassthroughSubject<Action?, Never>()
        sideEffects
            //.zip(state.dropFirst().zip(action))
            .flatMap { $0.publisher }
            .map { (UUID(), $0) }
            .handleEvents(receiveOutput: { currentSideEffects.send(currentSideEffects.value + [$0]) })
            .flatMap { id, sideEffect -> AnyPublisher<Action?, Never> in
                resolveSideEffect(sideEffect)
                    .map { $0 }

                    .catch { error -> AnyPublisher<Action?, Never> in
                        errors.send(errors.value + ["\(error)"])
                        return Just(nil).eraseToAnyPublisher()
                    }
                    .handleEvents(receiveOutput: { _ in
                        currentSideEffects.send(currentSideEffects.value.filter { $0.0 != id })
                    })
                    .eraseToAnyPublisher()
            }
            .sink(receiveValue: feedbacks.send)
            .store(in: &bag)
        return feedbacks
            .merge(with: action)
            .scan(initialValue, reducer)
            .handleEvents(receiveOutput:
                    state.send

            )
            .combineLatest(currentSideEffects.map { $0.count }, errors)
            .eraseToAnyPublisher()
    }

    func launch(_ action: Action?, then sideEffects: [SideEffect] = []) {
        self.action.send(action)
        self.sideEffects.send(sideEffects)
    }
}

class ItemStore: WithMachine {
    typealias State = [Item]
    // Output
    @Published private(set) var items: [Item]
    @Published private(set) var loading: Int = 0
    @Published private(set) var errors: [String] = []

    // Input
    enum Input {
        case add(Item)
        case delete(Item)
        case refresh(Item)
        case initialize([Item])
    }

    // Action
    enum Action {
        case append(Item)
        case remove(Item)
        case set([Item])
        case updateScore(UUID, Int)
        case updateDate(UUID, Date)
    }

    // SideEffect
    enum SideEffect {
        case fetchScore(Item)
        case fetchDate(Item)
    }

    internal var action = PassthroughSubject<Action?, Never>()
    internal var sideEffects = PassthroughSubject<[SideEffect], Never>()
    var bag = Set<AnyCancellable>()

    private var provider: ItemProvider

    init(initialValue: [Item] = []) {
        let provider = ItemProvider()
        self.provider = provider
        items = initialValue
        setup(initialValue: initialValue, bag: &bag)
            .sink { state, loading, errors in
                self.items = state
                self.loading = loading
                self.errors = errors
            }
            .store(in: &bag)
//        action
//            .scan(initialValue, reducer)
//            .assign(to: &$state)
//
//        sideEffect
//            .zip($state.dropFirst())
//            .compactMap { $0.0 }
//            .flatMap(sideEffect)
//            .compactMap { $0 }
//            .sink { [weak self] in self?.action.send($0) }
//            .store(in: &bag)
    }

    func send(_ input: Input) {
        switch input {
        case let .add(item):
            launch(.append(item), then: [.fetchScore(item), .fetchDate(item)])
        case let .delete(item):
            launch(.remove(item))
        case let .refresh(item):
            launch(nil, then: [.fetchScore(item), .fetchDate(item)])
        case let .initialize(array):
            launch(.set(array), then: array.flatMap { [.fetchScore($0), .fetchDate($0)] })
        }
    }

    func reducer(currentState: State, action: Action?) -> State {
        guard let action = action else { return currentState }
        switch action {
        case let .append(item):
            _ = (1...1_000_000).map {_ in Int.random(in: 1...100)}
            return currentState + [item]
        case let .remove(item):
            return currentState.filter { $0.id != item.id }
        case let .set(items):
            return items
        case let .updateDate(id, date):
            return currentState.updateItem(id: id, date: date)
        case let .updateScore(id, score):
            return currentState.updateItem(id: id, score: score)
        }
    }

    func resolveSideEffect(_ sideEffect: SideEffect) -> AnyPublisher<Action, Error> {
        switch sideEffect {
        case let .fetchScore(item):
            return provider.fetchScore()
                .map { Action.updateScore(item.id, $0) }
                .eraseToAnyPublisher()
        case let .fetchDate(item):
            return provider.fetchDate()
                .map { Action.updateDate(item.id, $0) }
                .eraseToAnyPublisher()
        }
    }
}

class ContentViewModel: ObservableObject {
    // Output
    @Published private(set) var items: [Item] = []
    @Published private(set) var loading: Int = 0
    @Published private(set) var errors: [String] = []

    // Input
    func tapAddButton() { add.send() }
    private var add = PassthroughSubject<Void, Never>()
    func onAppear() { initialize.send() }
    private var initialize = PassthroughSubject<Void, Never>()

    private var bag = Set<AnyCancellable>()
    init(store: ItemStore) {
        store.$items
            .assign(to: &$items)
        store.$loading
            .assign(to: &$loading)
        store.$errors
            .assign(to: &$errors)
        add
            .map { _ in Item(name: "Item \(store.items.count + 1)") }
            .sink { item in store.send(.add(item)) }
            .store(in: &bag)
        initialize
            .sink { _ in store.send(.initialize(Item.PREVIEWS)) }
            .store(in: &bag)
    }
}

struct ContentView2: View {
    @StateObject private var vm: ContentViewModel
    init(vm: ContentViewModel) {
        _vm = StateObject(wrappedValue: vm)
    }

    var body: some View {
        VStack {
            Text("we wait for \(vm.loading)")
            Text("errors \(vm.errors.count)")

            Button("Add", action: vm.tapAddButton)
            List(vm.items) { item in
                HStack {
                    Text(item.name)
                    Text(item.score?.description ?? "...")
                    if let date = item.date {
                        Text(date, style: .date)
                    } else {
                        Text("...")
                    }
                }
            }
            .onAppear(perform: vm.onAppear)
        }
    }
}

struct ContentView2_Previews: PreviewProvider {
    static var previews: some View {
        ContentView2(vm: ContentViewModel(store: ItemStore(initialValue: [])))
    }
}

extension Item {
    static var PREVIEWS: [Item] = (1 ... 14).map { .init(name: "Item \($0)") }
}
