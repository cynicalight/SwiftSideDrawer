//
//  SideDrawerDemo.swift
//  SideDrawerDemo
//

import SwiftUI
import SideDrawer

struct SideDrawerDemo: View {
    @State private var isMenuOpen = false

    var body: some View {
        SideDrawerContainer(
            isOpen: $isMenuOpen,
            menu: { SideMenu() },
            content: { MainContent(isMenuOpen: $isMenuOpen) }
        )
    }
}

private struct MainContent: View {
    @Binding var isMenuOpen: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Text("Main Content")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.cyan.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isMenuOpen.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
        }
    }
}

private struct SideMenu: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Circle()
                .fill(.white.opacity(0.25))
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                )

            Text("Menu")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 60)
        .background(Color.orange.ignoresSafeArea())
    }
}

#Preview {
    SideDrawerDemo()
}
