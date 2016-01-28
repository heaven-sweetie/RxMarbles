//
//  SourceTimelineView.swift
//  RxMarbles
//
//  Created by Roman Tutubalin on 21.01.16.
//  Copyright © 2016 Roman Tutubalin. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa

class SourceTimelineView: TimelineView {
    
    var addButton = UIButton(type: .ContactAdd)
    
    let longPressGestureRecorgnizer = UILongPressGestureRecognizer()
    
    private var _panEventView: EventView?
    private var _ghostEventView: EventView?
    
    private var _preLabel = UILabel()
    private var _postLabel = UILabel()
    
    private var _needRefreshEventViews: Bool = false
    
    var labelsText: (pre: String, post: String)? {
        didSet {
            if !labelsText!.pre.isEmpty {
                addSubview(_preLabel)
                _preLabel.text = labelsText!.pre
            }
            if !labelsText!.post.isEmpty {
                addSubview(_postLabel)
                _postLabel.text = labelsText!.post
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(frame: CGRect, scene: SceneView) {
        super.init(frame: frame)
        userInteractionEnabled = true
        clipsToBounds = false
        sceneView = scene
        
        longPressGestureRecorgnizer.minimumPressDuration = 0.0
        
        addGestureRecognizer(longPressGestureRecorgnizer)
        
        addButton.hidden = true
        _preLabel.font = UIFont.monospacedDigitSystemFontOfSize(16, weight: UIFontWeightRegular)
        _preLabel.textColor = .blackColor()
        _postLabel.font = UIFont.monospacedDigitSystemFontOfSize(16, weight: UIFontWeightRegular)
        _postLabel.textColor = .blackColor()
        _ = longPressGestureRecorgnizer
            .rx_event
            .subscribeNext {
                [unowned self] r in self._handleLongPressGestureRecognizer(r)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        _preLabel.frame = CGRectMake(0, 0, bounds.width, 20)
        _postLabel.frame = CGRectMake(0, bounds.height - 25, bounds.width, 20)
        
        addButton.center = CGPointMake(frame.size.width - 10.0, bounds.height / 2.0)
        
        if addButton.superview != nil {
            addButton.hidden = false
            timeArrow.frame = CGRectMake(timeArrow.frame.origin.x, timeArrow.frame.origin.y, timeArrow.frame.size.width - 23.0, timeArrow.frame.size.height)
            timeArrow.center.y = bounds.height / 2.0
        } else {
            addButton.hidden = true
        }
        
        if _needRefreshEventViews {
            _needRefreshEventViews = false
            sceneView.refreshSourceEventsCenters(self)
        }
    }
    
    private func _handleLongPressGestureRecognizer(r: UIGestureRecognizer) {
        let location = r.locationInView(self)
        switch r.state {
        case .Began:
            if let i = sourceEvents.indexOf({ $0.frame.contains(location) }) {
                _panEventView = sourceEvents[i]
            }
            if let panEventView = _panEventView {
                panEventView.animator?.removeBehavior(panEventView.snap!)
                
                _ghostEventView = EventView(recorded: panEventView.recorded)
                _ghostEventView!.center = CGPointMake(xPositionByTime(_ghostEventView!.recorded.time), bounds.height / 2)
                changeGhostColorAndAlpha(_ghostEventView!, recognizer: r)
                addSubview(_ghostEventView!)
                
                sceneView.showTrashView()
            }
        case .Changed:
            if let panEventView = _panEventView {
                let time = timeByXPosition(location.x)
                panEventView.center = CGPointMake(xPositionByTime(time), location.y)
                panEventView.recorded = RecordedType(time: time, event: panEventView.recorded.value)
                
                changeGhostColorAndAlpha(_ghostEventView!, recognizer: r)
                _ghostEventView!.recorded = panEventView.recorded
                _ghostEventView!.center = CGPointMake(xPositionByTime(time), bounds.height / 2)
                
                sceneView.resultTimeline.subject.onNext()
            }
        case .Ended, .Cancelled:
            _ghostEventView?.removeFromSuperview()
            _ghostEventView = nil
            
            if let panEventView = _panEventView {
                animatorAddBehaviorsToPanEventView(panEventView, recognizer: r, resultTimeline: sceneView.resultTimeline)
                panEventView.superview?.bringSubviewToFront(panEventView)
                let time = timeByXPosition(r.locationInView(self).x)
                panEventView.recorded = RecordedType(time: time, event: panEventView.recorded.value)
            }
            _panEventView = nil
            sceneView.resultTimeline.subject.onNext()
            sceneView.hideTrashView()
            
        default: break
        }
    }
    
    func addEventToTimeline(recorded: RecordedType, animator: UIDynamicAnimator!) {
        let v = EventView(recorded: recorded)
        if editing {
            v.addTapRecognizer()
        }
        addSubview(v)
        v.use(animator, timeLine: self)
        sourceEvents.append(v)
    }
    
     func changeGhostColorAndAlpha(ghostEventView: EventView, recognizer: UIGestureRecognizer) {
        if onDeleteZone(recognizer) == true {
            ghostEventView.shake()
            sceneView.trashView.shake()
            sceneView.trashView.alpha = 0.5
        } else {
            ghostEventView.stopAnimations()
            sceneView.trashView.stopAnimations()
            sceneView.trashView.alpha = 0.2
        }
        ghostEventView.setGhostColorOnDeleteZone(onDeleteZone(recognizer))
    }
    
    private func animatorAddBehaviorsToPanEventView(panEventView: EventView, recognizer: UIGestureRecognizer, resultTimeline: ResultTimelineView) {
        if let animator = panEventView.animator {
            let time = timeByXPosition(recognizer.locationInView(self).x)
            
            if onDeleteZone(recognizer) == true {
                panEventView.hideWithCompletion({ _ in
                    if let index = self.sourceEvents.indexOf(panEventView) {
                        self.sourceEvents.removeAtIndex(index)
                        self.sceneView.resultTimeline.subject.onNext()
                    }
                })
            } else {
                if let snap = panEventView.snap {
                    snap.snapPoint.x = xPositionByTime(time)
                    snap.snapPoint.y = center.y
                    animator.addBehavior(snap)
                }
            }
        }
    }
    
    private func onDeleteZone(recognizer: UIGestureRecognizer) -> Bool {
        let trash = sceneView.trashView
        let loc = recognizer.locationInView(superview)
        let eventViewFrame = CGRectMake(loc.x - 19, loc.y - 19, 38, 38)
        if CGRectIntersectsRect(trash.frame, eventViewFrame) {
            return true
        }
        return false
    }
    
    func showAddButton() {
        addSubview(addButton)
        removeGestureRecognizer(longPressGestureRecorgnizer)
    }
    
    func hideAddButton() {
        addButton.removeFromSuperview()
        addGestureRecognizer(longPressGestureRecorgnizer)
    }
    
    func addTapRecognizers() {
        sourceEvents.forEach { $0.addTapRecognizer() }
    }
    
    func removeTapRecognizers() {
        sourceEvents.forEach { $0.removeTapRecognizer() }
    }
    
    func allEventViewsAnimation() {
        sourceEvents.forEach { $0.scaleAnimation() }
    }
    
    override func setEditing() {
        super.setEditing()
        _needRefreshEventViews = true
        if editing {
            addTapRecognizers()
            showAddButton()
            addButton.addTarget(self, action: "addEventToTimeline:", forControlEvents: .TouchUpInside)
        } else {
            removeTapRecognizers()
            hideAddButton()
        }
        allEventViewsAnimation()
    }
    
    func addEventToTimeline(sender: UIButton) {
        NSNotificationCenter.defaultCenter().postNotificationName(Names.addEvent, object: sender)
    }
}