//
//  UIScrollView+ScrollAnimation.swift
//
//
//  Created by Jonathan Lott on 2/22/14.
//  Copyright (c) 2014 A Lott Of Ideas. All rights reserved.
//

import UIKit
import QuartzCore

private let kDefaultSetContentOffsetDuration: CFTimeInterval = 0.25

/// Constants used for Newton approximation of cubic function root.
private let kApproximationTolerance: Double = 0.00000001
private let kMaximumSteps: Int = 10

private func CGPointScalarMult(s: CGFloat, p: CGPoint) -> CGPoint {
    return CGPoint(x: s * p.x, y: s * p.y)
}

private func CGPointAdd(p: CGPoint, q: CGPoint) -> CGPoint {
    return CGPoint(x: p.x + q.x, y: p.y + q.y)
}

private func CGPointMinus(p: CGPoint, q: CGPoint) -> CGPoint {
    return CGPoint(x: p.x - q.x, y: p.y - q.y)
}

private func cubicFunctionValue(a: Double, b: Double, c: Double, d: Double, x: Double) -> Double {
    return (a * x * x * x) + (b * x * x) + (c * x) + d
}

private func cubicDerivativeValue(a: Double, b: Double, c: Double, d: Double, x: Double) -> Double {
    /// Derivation of the cubic (a*x*x*x)+(b*x*x)+(c*x)+d
    return (3 * a * x * x) + (2 * b * x) + c
}

private func rootOfCubic(a: Double, b: Double, c: Double, d: Double, startPoint: Double) -> Double {
    // We use 0 as start point as the root will be in the interval [0,1]
    var x = startPoint
    var lastX = 1.0

    // Approximate a root by using the Newton-Raphson method
    var y = 0
    while y <= kMaximumSteps && abs(lastX - x) > kApproximationTolerance {
        lastX = x
        x = x - (cubicFunctionValue(a: a, b: b, c: c, d: d, x: x) / cubicDerivativeValue(a: a, b: b, c: c, d: d, x: x))
        y += 1
    }
    return x
}

private func timingFunctionValue(function: CAMediaTimingFunction, x: Double) -> Double {
    var a = [Float](repeating: 0, count: 2)
    var b = [Float](repeating: 0, count: 2)
    var c = [Float](repeating: 0, count: 2)
    var d = [Float](repeating: 0, count: 2)

    function.getControlPoint(at: 0, values: &a)
    function.getControlPoint(at: 1, values: &b)
    function.getControlPoint(at: 2, values: &c)
    function.getControlPoint(at: 3, values: &d)

    // Look for t value that corresponds to provided x
    let t = rootOfCubic(a: -Double(a[0]) + 3 * Double(b[0]) - 3 * Double(c[0]) + Double(d[0]),
                        b: 3 * Double(a[0]) - 6 * Double(b[0]) + 3 * Double(c[0]),
                        c: -3 * Double(a[0]) + 3 * Double(b[0]),
                        d: Double(a[0]) - x,
                        startPoint: x)

    // Return corresponding y value
    let y = cubicFunctionValue(a: -Double(a[1]) + 3 * Double(b[1]) - 3 * Double(c[1]) + Double(d[1]),
                               b: 3 * Double(a[1]) - 6 * Double(b[1]) + 3 * Double(c[1]),
                               c: -3 * Double(a[1]) + 3 * Double(b[1]),
                               d: Double(a[1]),
                               x: t)

    return y
}

private class ScrollViewTimingDelegate: NSObject {

    weak var scrollView: UIScrollView?
    
    /// Display link used to trigger event to scroll the view.
    var displayLink: CADisplayLink?

    /// Timing function of an scroll animation.
    var timingFunction: CAMediaTimingFunction?

    /// Duration of an scroll animation.
    var duration: CFTimeInterval = 0.0

    /// States whether the animation has started.
    var animationStarted: Bool = false

    /// Time at the begining of an animation.
    var beginTime: CFTimeInterval = 0.0

    /// The content offset at the begining of an animation.
    var beginContentOffset: CGPoint = .zero

    /// The delta between the contentOffset at the start of the animation and
    /// the contentOffset at the end of the animation.
    var deltaContentOffset: CGPoint = .zero

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Set ContentOffset with Custom Animation

    func setContentOffset(_ contentOffset: CGPoint, withTimingFunction timingFunction: CAMediaTimingFunction) {
        self.setContentOffset(contentOffset, withTimingFunction: timingFunction, duration: kDefaultSetContentOffsetDuration)
    }

    func setContentOffset(_ contentOffset: CGPoint, withTimingFunction timingFunction: CAMediaTimingFunction, duration: CFTimeInterval) {
        
        guard let scrollView = self.scrollView else { return }
        
        self.duration = duration
        self.timingFunction = timingFunction
        
        self.deltaContentOffset = CGPointMinus(p: contentOffset, q: scrollView.contentOffset)
        
        if self.displayLink == nil {
            self.displayLink = CADisplayLink(target: self, selector: #selector(updateContentOffset(_:)))
            self.displayLink?.preferredFramesPerSecond = 60
            self.displayLink?.add(to: .current, forMode: .common)
        } else {
            self.displayLink?.isPaused = false
        }
    }

    @objc private func updateContentOffset(_ displayLink: CADisplayLink) {
        guard let timingFunction = self.timingFunction else { return }
        
        if self.beginTime == 0.0 {
            self.beginTime = displayLink.timestamp
            self.beginContentOffset = self.scrollView?.contentOffset ?? .zero
        } else {
            let deltaTime = displayLink.timestamp - self.beginTime
            
            // Ratio of duration that went by
            let progress = CGFloat(deltaTime / self.duration)
            if progress < 1.0 {
                // Ratio adjusted by timing function
                let adjustedProgress = CGFloat(timingFunctionValue(function: timingFunction, x: Double(progress)))
                if 1 - adjustedProgress < 0.001 {
                    stopAnimation()
                } else {
                    updateProgress(adjustedProgress)
                }
            } else {
                stopAnimation()
            }
        }
    }

    private func updateProgress(_ progress: CGFloat) {
        guard let scrollView = self.scrollView else { return }
        let currentDeltaContentOffset = CGPointScalarMult(s: progress, p: self.deltaContentOffset)
        scrollView.contentOffset = CGPointAdd(p: self.beginContentOffset, q: currentDeltaContentOffset)
    }

    private func stopAnimation() {
        self.displayLink?.isPaused = true
        self.beginTime = 0.0
        
        guard let scrollView = self.scrollView else { return }
        
        scrollView.contentOffset = CGPointAdd(p: self.beginContentOffset, q: self.deltaContentOffset)
        
        if let delegate = scrollView.delegate, delegate.responds(to: #selector(UIScrollViewDelegate.scrollViewDidEndScrollingAnimation(_:))) {
            // inform delegate about end of animation
            delegate.scrollViewDidEndScrollingAnimation?(scrollView)
        }
    }
}

extension UIScrollView {
    
    private var scrollViewTimingDelegate: ScrollViewTimingDelegate? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.timingDelegate) as? ScrollViewTimingDelegate
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.timingDelegate, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private struct AssociatedKeys {
        static var timingDelegate: UInt8 = 0
    }
    
    /**
     Sets the contentOffset of the ScrollView and animates the transition. The
     animation takes 0.25 seconds.
     
     - parameter contentOffset:  A point (expressed in points) that is offset from the content view’s origin.
     - parameter timingFunction: A timing function that defines the pacing of the animation.
     */
    func setContentOffset(_ contentOffset: CGPoint, withTimingFunction timingFunction: CAMediaTimingFunction) {
        if self.scrollViewTimingDelegate == nil {
            let timingDelegate = ScrollViewTimingDelegate()
            timingDelegate.scrollView = self
            self.scrollViewTimingDelegate = timingDelegate
        }
        self.scrollViewTimingDelegate?.setContentOffset(contentOffset, withTimingFunction: timingFunction)
    }

    /**
     Sets the contentOffset of the ScrollView and animates the transition.
     
     - parameter contentOffset:  A point (expressed in points) that is offset from the content view’s origin.
     - parameter timingFunction: A timing function that defines the pacing of the animation.
     - parameter duration:       Duration of the animation in seconds.
     */
    func setContentOffset(_ contentOffset: CGPoint, withTimingFunction timingFunction: CAMediaTimingFunction, duration: CFTimeInterval) {
        if self.scrollViewTimingDelegate == nil {
            let timingDelegate = ScrollViewTimingDelegate()
            timingDelegate.scrollView = self
            self.scrollViewTimingDelegate = timingDelegate
        }
        self.scrollViewTimingDelegate?.setContentOffset(contentOffset, withTimingFunction: timingFunction, duration: duration)
    }
}
