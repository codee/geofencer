import CoreLocation
import MapKit
import UIKit

class ViewController: UIViewController, MKMapViewDelegate {
    let locationManager = CLLocationManager()

    var points:[MKPointAnnotation]?
    var polygon:MKPolygon?

    let diskStore = DiskStore()

    var regions:[Region] = [] {
        didSet {
            for region in oldValue {
                region.overlays.forEach({ mapView.removeOverlay($0) })
                region.annotations.forEach({ mapView.removeAnnotation($0) })
            }

            for region in regions {
                region.overlays.forEach({ mapView.addOverlay($0) })
                region.annotations.forEach({ mapView.addAnnotation($0) })
            }

            shareButton.enabled = (regions.count > 0)
            resetButton.enabled = (regions.count > 0)
            diskStore.save(regions)
        }

    }

    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var addButton: UIButton!
    @IBOutlet weak var doneButton: UIBarButtonItem!
    @IBOutlet weak var shareButton: UIBarButtonItem!
    @IBOutlet weak var resetButton: UIBarButtonItem!

    @IBAction func didTapAddButton(sender: AnyObject) {
        if let coordinate = mapView.userLocation.location?.coordinate {
            addCoordinate(coordinate)
        }
    }
    
    @IBAction func didTapDoneButton(sender: AnyObject) {
        if let points = self.points {
            let alert = UIAlertController(title: "Name This Region", message: nil, preferredStyle: .Alert)
            alert.addTextFieldWithConfigurationHandler({ (field) in })
            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: { (action) in
                self.dismissViewControllerAnimated(true, completion: nil)

                if let title = alert.textFields?.first?.text {
                    let polygon = PolygonRegion(points: points, title: title)
                    self.regions.append(polygon)

                    self.resetCurrentRegion()
                }

            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: { (action) in
                self.dismissViewControllerAnimated(true, completion: nil)
            }))

            self.presentViewController(alert, animated: true, completion: nil)
        }
    }

    @IBAction func didTapResetButton(sender: AnyObject) {
        let alert = UIAlertController(title: "Reset All Data", message: "Are you sure you'd like to erase all local regions?", preferredStyle: .Alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .Default, handler: { (action) in
            self.dismissViewControllerAnimated(true, completion: nil)

            self.regions = []
            self.points = nil
            self.polygon = nil
        }))

        alert.addAction(UIAlertAction(title: "No", style: .Cancel, handler: { (action) in
            self.dismissViewControllerAnimated(true, completion: nil)
        }))

        self.presentViewController(alert, animated: true, completion: nil)
    }

    @IBAction func didTapShareButton(sender: AnyObject) {
        let json = regionsAsJSON(self.regions)
        let activityViewController = UIActivityViewController(activityItems: [json as NSString], applicationActivities: nil)
        presentViewController(activityViewController, animated: true, completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        locationManager.requestWhenInUseAuthorization()

        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.FollowWithHeading, animated: true)

        regions = diskStore.load()
    }

    //-

    func addCoordinate(coordinate:CLLocationCoordinate2D) {
        let point = MKPointAnnotation()
        point.coordinate = coordinate
        point.title = "Region Vertex"

        if (self.points == nil) {
            self.points = []
        }
        self.points!.append(point)
        self.mapView.addAnnotation(point)

        recalculatePolygon()
        recalculateDoneButton()
    }

    func resetCurrentRegion() {
        if let points = points {
            points.forEach({ (point) in
                self.mapView.removeAnnotation(point)
            })
        }

        if let polygon = polygon {
            self.mapView.removeAnnotation(polygon)
            self.mapView.removeOverlay(polygon)
        }

        self.points = []
        self.polygon = nil

        self.doneButton.enabled = false
    }

    func recalculatePolygon() {
        if let points = points {
            if let polygon = polygon {
                mapView.removeOverlay(polygon)
                mapView.removeAnnotation(polygon)
            }

            polygon = PolygonRegion.polygonFromPoints(points)

            if let polygon = polygon {
                polygon.title = "Current Region"
                mapView.addOverlay(polygon)
                mapView.addAnnotation(polygon)
            }
        }
    }

    func recalculateDoneButton() {
        doneButton.enabled = (points?.count > 0)
    }

    //-
    // MKMapViewDelegate

    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation.isKindOfClass(MKPointAnnotation.self) || annotation.isKindOfClass(MKPolygon.self) {
            let identifier = NSStringFromClass(MKPinAnnotationView.self)
            var pinView = mapView.dequeueReusableAnnotationViewWithIdentifier(identifier) as? MKPinAnnotationView
            if (pinView == nil) {
                pinView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }

            if annotation.isKindOfClass(MKPointAnnotation.self) {
                pinView?.pinTintColor = MKPinAnnotationView.redPinColor()
                pinView?.canShowCallout = true

                let button = UIButton(type: .Custom)
                button.setTitleColor(UIColor.redColor(), forState: .Normal)
                button.tintColor = UIColor.redColor()
                button.setTitle("X", forState: .Normal)
                button.sizeToFit()
                pinView?.rightCalloutAccessoryView = button
            } else {
                pinView?.pinTintColor = MKPinAnnotationView.greenPinColor()
                pinView?.canShowCallout = true

                let button = UIButton(type: .Custom)
                if let title = annotation.title {
                    if (title == "Current Region") {
                        button.setTitleColor(UIColor.redColor(), forState: .Normal)
                        button.tintColor = UIColor.redColor()
                        button.setTitle("X", forState: .Normal)
                    } else {
                        button.setTitleColor(self.view.tintColor, forState: .Normal)
                        button.setTitle("Edit", forState: .Normal)
                    }
                }
                button.sizeToFit()
                pinView?.rightCalloutAccessoryView = button
            }
            
            return pinView
        }
        return nil
    }

    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay.isKindOfClass(MKPolygon.self) {
            let renderer = MKPolygonRenderer(polygon: overlay as! MKPolygon)
            renderer.fillColor = UIColor.cyanColor().colorWithAlphaComponent(0.2)
            renderer.strokeColor = UIColor.blueColor().colorWithAlphaComponent(0.7)
            renderer.lineWidth = 0.5;

            return renderer
        }

        // This case should never be reached, and fail silently.
        // But this function doesn't have a return type of Optional.
        // Obj-C interop is hard!
        return MKCircleRenderer()
    }

    func mapView(mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        if (view.annotation!.isKindOfClass(MKPointAnnotation.self)) {
            if let point = view.annotation as? MKPointAnnotation {
                self.mapView.removeAnnotation(point)
                self.points = self.points?.filter({
                    return !($0.coordinate.latitude == point.coordinate.latitude &&
                        $0.coordinate.longitude == point.coordinate.longitude)
                })
                recalculatePolygon()
            }
        } else {
            if let polygon = view.annotation as? MKPolygon {
                if let index = self.regions.indexOf({ $0.annotations == [polygon] }) {
                    let region = self.regions[index]
                    self.regions.removeAtIndex(index)

                    self.points?.forEach({ self.mapView.removeAnnotation($0) })
                    self.points = []

                    recalculatePolygon()

                    region.points.forEach({ addCoordinate($0) })
                    self.title = region.title
                } else {
                    self.resetCurrentRegion()
                }
            }
        }
    }
}

