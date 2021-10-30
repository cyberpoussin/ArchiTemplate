////
////  ContentView.swift
////  ArchiTemplate
////
////  Created by Admin on 23/10/2021.
////
//
//import Combine
//import SwiftUI
//
//// MARK: Service
//
//class MockService {
//    func fetch<Output>(_ value: Output) -> AnyPublisher<Output, Error> {
//        let publisher = PassthroughSubject<Output, Error>()
//        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 0 ... 1)) {
//            guard Int.random(in: 1 ... 100) != 1 else {
//                return publisher.send(completion: .failure(URLError(.badServerResponse)))
//            }
//            publisher.send(value)
//            publisher.send(completion: .finished)
//        }
//        return publisher.eraseToAnyPublisher()
//    }
//}
//
//// MARK: Model
//
//struct Item: Identifiable {
//    let id = UUID()
//    var name: String
//    var score: Int?
//    var date: Date?
//}
//
//// MARK: Provider
//
//class ItemProvider {
//    let service = MockService()
//    func fetchScore() -> AnyPublisher<Int, Error> {
//        service.fetch(Int.random(in: 1 ... 100))
//            .eraseToAnyPublisher()
//    }
//
//    func fetchDate() -> AnyPublisher<Date, Error> {
//        service.fetch(Date(timeIntervalSinceNow: Double.random(in: 10000 ... 100000)))
//            .eraseToAnyPublisher()
//    }
//}
//
//// MARK: Store
//
//
//
//
//class ItemStore {
//    // Output
//    @Published private(set) var state: [Item]
//
//    // Input
//    enum Input {
//        case add(Item)
//        case delete(Item)
//        case refresh(Item)
//        case initialize([Item])
//    }
//    
//    // Action
//    enum Action {
//        case append(Item)
//        case remove(Item)
//        case set([Item])
//
//        case updateScore(UUID, Int)
//        case updateDate(UUID, Date)
//    }
//    
//    enum SideEffect {
//        case fillItem(Item)
//        case fillItems([Item])
//    }
//
//    private var action = PassthroughSubject<Action?, Never>()
//    private var sideEffect = PassthroughSubject<SideEffect?, Never>()
//
//
//    private var bag = Set<AnyCancellable>()
//    init(initialValue: [Item] = []) {
//        state = initialValue
//        let provider = ItemProvider()
//        
//        action
//            .scan(initialValue) { currentState, action in
//                guard let action = action else { return currentState }
//                switch action {
//                case let .append(item):
//                    return currentState + [item]
//                case let .remove(item):
//                    return currentState.filter { $0.id != item.id }
//                case let .set(items):
//                    return items
//                case let .updateDate(id, date):
//                    return currentState.map {item in
//                        guard item.id == id else {return item}
//                        var newItem = item
//                        newItem.date = date
//                        return newItem
//                    }
//                case let .updateScore(id, score):
//                    return currentState.map {item in
//                        guard item.id == id else {return item}
//                        var newItem = item
//                        newItem.score = score
//                        return newItem
//                    }
//                }
//            }
//            .assign(to: &$state)
//        
//        sideEffect
//            .zip($state.dropFirst())
//            .compactMap { $0.0 }
//            .flatMap { [fetchItemInfos] sideEffect -> AnyPublisher<Action?, Never> in
//                switch sideEffect {
//                case let .fillItem(item):
//                    return fetchItemInfos(item, provider)
//                case let .fillItems(items):
//                    return items.publisher
//                        .flatMap {
//                            fetchItemInfos($0, provider)
//                        }
//                        .eraseToAnyPublisher()
//                }
//                
//            }
//            .compactMap { $0 }
//            .sink { [weak self] in self?.action.send($0) }
//            .store(in: &bag)
//        
//        
//    }
//
//    func send(_ input: Input) {
//        switch input {
//        case .add(let item):
//            launch(.append(item), then: .fillItem(item))
//        case .delete(let item):
//            launch(.remove(item))
//        case .refresh(let item):
//            launch(nil, then: .fillItem(item))
//        case .initialize(let array):
//            launch(.set(array), then: .fillItems(array))
//        }
//    }
//    
//    func launch(_ action: Action?, then sideEffect: SideEffect? = nil) {
//        self.action.send(action)
//        self.sideEffect.send(sideEffect)
//    }
//    
//    func fetchItemInfos(_ item: Item, with provider: ItemProvider) -> AnyPublisher<Action?, Never>{
//        let fetchScore = provider.fetchScore()
//            .map { Action.updateScore(item.id, $0) }
//            .replaceError(with: nil)
//        let fetchDate = provider.fetchDate()
//            .map { Action.updateDate(item.id, $0) }
//            .replaceError(with: nil)
//        return Publishers.Merge(fetchDate, fetchScore)
//            .eraseToAnyPublisher()
//    }
//}
//
//class ContentViewModel: ObservableObject {
//    // Output
//    @Published private(set) var items: [Item] = []
//
//    // Input
//    func tapAddButton() { add.send() }
//    private var add = PassthroughSubject<Void, Never>()
//    func onAppear() { initialize.send() }
//    private var initialize = PassthroughSubject<Void, Never>()
//
//    private var bag = Set<AnyCancellable>()
//    init(store: ItemStore) {
//        store.$state
//            .assign(to: &$items)
//        add
//            .map { _ in Item(name: "Item \(store.state.count + 1)") }
//            .sink { item in store.send(.add(item)) }
//            .store(in: &bag)
//        initialize
//            .sink { item in store.send(.initialize(Item.PREVIEWS)) }
//            .store(in: &bag)
//
//    }
//}
//
//struct ContentView2: View {
//    @StateObject private var vm: ContentViewModel
//    init(vm: ContentViewModel) {
//        _vm = StateObject(wrappedValue: vm)
//    }
//
//    var body: some View {
//        VStack {
//            Button("Add", action: vm.tapAddButton)
//            List(vm.items) { item in
//                HStack {
//                    Text(item.name)
//                    Text(item.score?.description ?? "...")
//                    if let date = item.date {
//                        Text(date, style: .date)
//                    } else {
//                        Text("...")
//                    }
//                }
//            }
//            .onAppear(perform: vm.onAppear)
//        }
//    }
//}
//
//struct ContentView2_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView2(vm: ContentViewModel(store: ItemStore(initialValue:[])))
//    }
//}
//
//extension Item {
//    static var PREVIEWS: [Item] = (1 ... 4).map { .init(name: "Item \($0)") }
//}
