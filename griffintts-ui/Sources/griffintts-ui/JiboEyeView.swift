import SwiftUI

struct JiboEyeView: View {
    // Animation properties
    var blinkScaleY: CGFloat
    var talkScale: CGFloat
    var lookOffset: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let eyeRadius = size * 0.4
            let pupilRadius = eyeRadius * 0.45
            
            ZStack {
                // Background dark void
                Color.black
                
                // Jibo's blue glowing outer ring (diffuse aura)
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.blue.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: eyeRadius * 1.5
                    ))
                    .frame(width: eyeRadius * 3, height: eyeRadius * 3)
                
                // Jibo's white screen bezel circle
                Circle()
                    .fill(Color.black)
                    .frame(width: size, height: size)
                
                // The main Jibo Eye (white core of the eye)
                Group {
                    ZStack {
                        // Core outer eye (white glowing sphere)
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color.white, Color(white: 0.95)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .shadow(color: Color.blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        
                        // Pupil (slightly darker inner reflection)
                        Circle()
                            .fill(Color(white: 0.15))
                            .frame(width: pupilRadius, height: pupilRadius)
                            // Look offset for cursor-tracking
                            .offset(lookOffset)
                            .animation(.easeOut(duration: 0.15), value: lookOffset)
                        
                        // Glint/Reflection inside pupil (upper-left shiny light)
                        Circle()
                            .fill(Color.white.opacity(0.8))
                            .frame(width: pupilRadius * 0.3, height: pupilRadius * 0.3)
                            .offset(x: lookOffset.width - pupilRadius * 0.25, y: lookOffset.height - pupilRadius * 0.25)
                            .animation(.easeOut(duration: 0.15), value: lookOffset)
                    }
                }
                // Warp, squash, stretch, blinking, and talking animations
                .frame(width: eyeRadius * 2, height: eyeRadius * 2)
                .scaleEffect(x: talkScale, y: blinkScaleY * talkScale, anchor: .center)
                .animation(.easeInOut(duration: 0.08), value: blinkScaleY)
                .animation(.spring(response: 0.15, dampingFraction: 0.6), value: talkScale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
