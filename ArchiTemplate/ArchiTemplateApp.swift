//
//  ArchiTemplateApp.swift
//  ArchiTemplate
//
//  Created by Admin on 23/10/2021.
//

import SwiftUI

@main
struct ArchiTemplateApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView2(vm: ContentViewModel(store: ItemStore(initialValue: [])))
            
        }
    }
}
