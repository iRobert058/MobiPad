/// How the Mac companion app advertises itself on the local network (CR-02).
public enum MobiPadService {
    /// Bonjour service type. The iPhone app must list this under `NSBonjourServices` in its Info.plist.
    public static let bonjourType = "_mobipad._udp"
    public static let bonjourDomain = "local."
}
