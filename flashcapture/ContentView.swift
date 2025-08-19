//
//  ContentView.swift
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                NavigationLink(destination: VideoView()) {
                    Text("Video")
                        .font(.title)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                        .foregroundColor(.white)
                }
                Spacer()
                NavigationLink(destination: PhotoView()) {
                    Text("Photo")
                        .font(.title)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue))
                        .foregroundColor(.white)
                }
            }
            .navigationTitle("Home")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
