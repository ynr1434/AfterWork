import SwiftUI

/// Static Feed discovery content. These ideas are not backend activities and never
/// participate in Save, Join, or other Supabase engagement requests.
struct AlmatyPlaceSuggestion: Identifiable {
    let id: String
    let name: String
    let category: String
    let area: String
    let pitch: String
    let details: String
    let groupIdea: String
    let imageName: String
    let symbol: String
    let tint: Color
}

enum AlmatyPlaceSuggestions {
    static let all: [AlmatyPlaceSuggestion] = [
        .init(id: "line-brew", name: "Line Brew", category: "Steakhouse · Pub", area: "City centre",
              pitch: "A slow dinner, grilled food and something cold after work.",
              details: "A relaxed steakhouse-and-pub style evening: meet after work, settle in for a full dinner, and leave room for a long conversation.",
              groupIdea: "Good for a team catch-up.", imageName: "FeedPlace01", symbol: "flame.fill", tint: .orange),
        .init(id: "pinta", name: "PINTA", category: "Pub", area: "Tulebaeva area",
              pitch: "An easygoing pub stop when nobody wants to overthink the plan.",
              details: "Keep the plan casual with pub food and an informal table where friends can join without turning the evening into an occasion.",
              groupIdea: "Good for an easy Friday.", imageName: "FeedPlace02", symbol: "mug.fill", tint: .brown),
        .init(id: "daredzhani", name: "Daredzhani", category: "Georgian", area: "Dostyk side",
              pitch: "Khinkali, khachapuri and plenty to pass around the table.",
              details: "Make dinner about sharing: order Georgian favourites for the middle of the table and let everyone try a bit of everything.",
              groupIdea: "Good for a shared feast.", imageName: "FeedPlace03", symbol: "takeoutbag.and.cup.and.straw.fill", tint: .red),
        .init(id: "sandyq", name: "Sandyq", category: "Kazakh cuisine", area: "Abylai Khan Avenue",
              pitch: "A dinner built around Kazakh hospitality and traditional recipes.",
              details: "Invite the group for a more local-feeling dinner, with traditional flavours and a setting suited to an unhurried meal together.",
              groupIdea: "Good for a taste of local culture.", imageName: "FeedPlace04", symbol: "sun.max.fill", tint: .orange),
        .init(id: "auyl", name: "AUYL", category: "Modern Kazakh", area: "Medeu side",
              pitch: "A destination dinner with a mountain-side atmosphere.",
              details: "Turn dinner into a little outing: plan ahead, bring the group together, and make the atmosphere part of the evening.",
              groupIdea: "Good for a special occasion.", imageName: "FeedPlace05", symbol: "mountain.2.fill", tint: .green),
        .init(id: "paulaner", name: "Paulaner Bräuhaus", category: "Brewpub", area: "Mukanova Street",
              pitch: "Bavarian comfort food and house-brewed beer in a lively room.",
              details: "A lively brewpub-style meetup for hearty food and a group catch-up. Add the time in your activity so everyone can plan around it.",
              groupIdea: "Good for a lively group night.", imageName: "FeedPlace06", symbol: "beer.mug.fill", tint: .yellow),
        .init(id: "french-42", name: "French 42", category: "Cocktail bar", area: "City centre",
              pitch: "Cocktails and a more intimate start to the evening.",
              details: "Start the night with a smaller, conversation-first gathering. It also works as the first stop before the group heads somewhere else.",
              groupIdea: "Good for cocktails and conversation.", imageName: "FeedPlace07", symbol: "wineglass.fill", tint: .purple),
        .init(id: "yellow-door", name: "Yellow Door", category: "Speakeasy bar", area: "City centre",
              pitch: "A tucked-away cocktail-bar idea for a late catch-up.",
              details: "Choose this for a late, cosy catch-up. Share the plan with friends first and check the venue's current entry details before heading out.",
              groupIdea: "Good for a birthday toast.", imageName: "FeedPlace08", symbol: "door.left.hand.closed", tint: .yellow),
        .init(id: "bowler", name: "Bowler Coffee Roasters", category: "Coffee", area: "Green Bazaar area",
              pitch: "Coffee, something sweet and a relaxed daytime meetup.",
              details: "A lower-key alternative to dinner: set a daytime time, meet for coffee and a treat, and keep the plan easy to join.",
              groupIdea: "Good for a weekend coffee.", imageName: "FeedPlace09", symbol: "cup.and.saucer.fill", tint: .brown),
        .init(id: "vista", name: "Vista", category: "Restaurant · Views", area: "Esentai area",
              pitch: "A dress-up dinner idea with a wide city view.",
              details: "Make the setting part of a group celebration. Set expectations in the activity description and check reservations and current details directly.",
              groupIdea: "Good for a team celebration.", imageName: "FeedPlace10", symbol: "sparkles", tint: .indigo),
        .init(id: "parmigiano", name: "Parmigiano Ristorante", category: "Italian", area: "City centre",
              pitch: "Handmade pasta and an unhurried Italian-style dinner.",
              details: "A comfortable pick for a longer dinner. Choose a start time, invite the group, and mention any shared-dish or dietary plans in the activity.",
              groupIdea: "Good for a long Italian dinner.", imageName: "FeedPlace11", symbol: "fork.knife", tint: .red),
        .init(id: "tary", name: "TARY", category: "Ethno café", area: "Almaty",
              pitch: "A coffee stop with a local twist and room for a proper catch-up.",
              details: "A relaxed café meetup for a quick catch-up or an easy start to the day. The exact venue location can be adjusted in the activity form.",
              groupIdea: "Good for a coffee break.", imageName: "FeedPlace12", symbol: "cup.and.saucer.fill", tint: .teal)
    ]
}
