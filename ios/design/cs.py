#!/usr/bin/env python3
"""Writes Watchlist/Resources/Localizable.xcstrings: English plurals and the Czech translation.

English keys come from the Swift sources. Edit CS (or PLURALS) and run: python3 design/cs.py
"""
import json
from pathlib import Path

CATALOG = Path(__file__).resolve().parent.parent / "Watchlist/Resources/Localizable.xcstrings"

CS = {
    "%@ left": "zbývá %@",
    "%lld / %lld": "%lld / %lld",
    "%lld installed": "nainstalováno: %lld",
    "%lld of %lld": "%lld z %lld",
    "%lld of %lld watched": "zhlédnuto %lld z %lld",
    "About": "O aplikaci",
    "Account": "Účet",
    "Add": "Přidat",
    "Add a TMDb API key in Settings to search and fill in details automatically.": "Přidejte v Nastavení klíč k TMDb API a podrobnosti se doplní samy.",
    "Add a genre": "Přidat žánr",
    "Add and start another": "Přidat a začít další",
    "Add movies and shows you want to see. Search TMDb or type a title.": "Přidejte filmy a seriály, které chcete vidět. Vyhledejte je na TMDb nebo napište název.",
    "Add the number of episodes when editing the show, or a TMDb key in Settings.": "Při úpravě seriálu zadejte počet dílů, nebo v Nastavení přidejte klíč k TMDb.",
    "Add title": "Přidat titul",
    "Add titles": "Přidat tituly",
    "Add titles from your watchlist.": "Přidejte tituly ze svého watchlistu.",
    "Add titles to the collection first.": "Nejdřív do kolekce přidejte tituly.",
    "Add to a collection": "Přidat do kolekce",
    "Add to favorites": "Přidat mezi oblíbené",
    "Add your first title": "Přidat první titul",
    "All": "Vše",
    "All episodes": "Všechny díly",
    "All watched": "Vše zhlédnuto",
    "Another device kept changing the watchlist. Try again.": "Watchlist se mezitím měnil na jiném zařízení. Zkuste to znovu.",
    "Anything to remember": "Cokoli si chcete zapamatovat",
    "Appearance": "Vzhled",
    "Ascending": "Vzestupně",
    "Automatic": "Automaticky",
    "Available on": "K dispozici na",
    "Back": "Zpět",
    "Back it up": "Zálohujte",
    "By type": "Podle typu",
    "Cancel": "Zrušit",
    "Change collections": "Změnit kolekce",
    "Choose a photo": "Vybrat fotku",
    "Choose photo": "Vybrat fotku",
    "Clear filters": "Zrušit filtry",
    "Clears the saved time and takes it out of Jump back in.": "Smaže uložený čas a odebere titul z Vrátit se ke sledování.",
    "Close": "Zavřít",
    "Collection not found": "Kolekce nenalezena",
    "Collections": "Kolekce",
    "Completed": "Zhlédnuto",
    "Continue watching": "Pokračovat ve sledování",
    "Continue watching %@": "Pokračovat ve sledování: %@",
    "Couldn't check the marketplace.": "Marketplace se nepodařilo zkontrolovat.",
    "Couldn't load the page": "Stránku se nepodařilo načíst",
    "Couldn't reach Nucleus ID. Check your connection.": "Nucleus ID je nedostupné. Zkontrolujte připojení.",
    "Couldn't send it (%lld).": "Nepodařilo se odeslat (%lld).",
    "Cover": "Obálka",
    "Create “%@”": "Vytvořit „%@“",
    "Custom": "Vlastní",
    "Custom link": "Vlastní odkaz",
    "Dark": "Tmavý",
    "Data": "Data",
    "Date added": "Datum přidání",
    "Default": "Výchozí",
    "Delete": "Smazat",
    "Delete Nucleus ID account": "Smazat účet Nucleus ID",
    "Delete collection": "Smazat kolekci",
    "Delete title": "Smazat titul",
    "Delete “%@”?": "Smazat „%@“?",
    "Descending": "Sestupně",
    "Description": "Popis",
    "Details": "Podrobnosti",
    "Discard": "Zahodit",
    "Discard this report?": "Zahodit toto hlášení?",
    "Dismiss": "Zavřít",
    "Done": "Hotovo",
    "Each title can override this when you edit it.": "Každý titul to může mít při úpravě jinak.",
    "Edit": "Upravit",
    "Edit collection": "Upravit kolekci",
    "Edit title": "Upravit titul",
    "Email (optional)": "E-mail (nepovinné)",
    "Episodes": "Díly",
    "Every title is already here.": "Všechny tituly už tu jsou.",
    "Everything you want to watch, in one place.": "Všechno, co chcete vidět, na jednom místě.",
    "Export backup": "Exportovat zálohu",
    "Export to a file and bring it to another device any time.": "Exportujte do souboru a kdykoli přeneste na jiné zařízení.",
    "Exported %@.": "Exportováno %@.",
    "Favorite": "Oblíbené",
    "Favorites only": "Jen oblíbené",
    "Fills in missing posters, genres, runtimes and where to watch. Takes about %lld seconds.": "Doplní chybějící plakáty, žánry, délky a kde sledovat. Zabere asi %lld s.",
    "Filter this collection": "Filtrovat kolekci",
    "Finished watching?": "Dokoukáno?",
    "Forget saved position": "Zapomenout uloženou pozici",
    "Forward": "Vpřed",
    "Genres": "Žánry",
    "Get a TMDb key": "Získat klíč k TMDb",
    "Go to start page": "Přejít na úvodní stránku",
    "Group titles into lists like “Weekend picks” or “Christmas”.": "Seskupte tituly do seznamů jako „Na víkend“ nebo „Vánoce“.",
    "Help": "Pomoc",
    "Image": "Obrázek",
    "Import backup": "Importovat zálohu",
    "In progress": "Rozkoukané",
    "It may have been deleted on another device.": "Možná byl smazán na jiném zařízení.",
    "It's removed from your watchlist and every collection.": "Zmizí z watchlistu i ze všech kolekcí.",
    "Jump back in": "Vrátit se ke sledování",
    "Keep and merge": "Ponechat a sloučit",
    "Keep on this device": "Ponechat v zařízení",
    "Large posters": "Velké plakáty",
    "Layout": "Rozložení",
    "Light": "Světlý",
    "Links": "Odkazy",
    "List": "Seznam",
    "Lives on your phone": "Žije ve vašem telefonu",
    "Mark all": "Označit vše",
    "Mark as watched": "Označit jako zhlédnuté",
    "Mark episode watched": "Označit díl jako zhlédnutý",
    "Mark season unwatched": "Označit sérii jako nezhlédnutou",
    "Mark season watched": "Označit sérii jako zhlédnutou",
    "Marked S%lld E%lld as watched": "S%lld E%lld označeno jako zhlédnuté",
    "Merge with this device": "Sloučit s tímto zařízením",
    "More": "Další",
    "Movie": "Film",
    "Movies": "Filmy",
    "Name": "Název",
    "Needs an API key": "Vyžaduje klíč k API",
    "New collection": "Nová kolekce",
    "No TMDb API key set. Add one in Settings.": "Chybí klíč k TMDb API. Přidejte ho v Nastavení.",
    "No account needed. Your list stays on this device.": "Bez účtu. Váš seznam zůstává v tomto zařízení.",
    "No collections yet": "Zatím žádné kolekce",
    "No collections yet. Type a name to create one.": "Zatím žádné kolekce. Napište název a vytvořte ji.",
    "No episode data": "Chybí údaje o dílech",
    "No matches": "Nic nenalezeno",
    "No plugins": "Žádné pluginy",
    "None": "Žádné",
    "Not in this version": "Není v této verzi",
    "Not included in this version of the app. Update the app or contact the developer.": "V této verzi aplikace není. Aktualizujte aplikaci nebo kontaktujte vývojáře.",
    "Not synced yet": "Zatím nesynchronizováno",
    "Notes": "Poznámky",
    "Nothing fits these filters.": "Těmto filtrům nic neodpovídá.",
    "Nothing here matches “%@”.": "Pro „%@“ tu nic není.",
    "Nothing here yet": "Zatím tu nic není",
    "Nothing to watch yet": "Zatím nic ke zhlédnutí",
    "Nucleus ID": "Nucleus ID",
    "Offline. Changes sync when you're back.": "Offline. Změny se synchronizují, až budete zpět.",
    "Open": "Otevřít",
    "Open in Safari": "Otevřít v Safari",
    "Open links in the app": "Otevírat odkazy v aplikaci",
    "Open on": "Otevřít na",
    "Open on %@": "Otevřít na %@",
    "Open on click": "Otevřít po klepnutí",
    "Optional": "Nepovinné",
    "Or sync it": "Nebo synchronizujte",
    "Paste URL": "Vložit URL",
    "Pick titles": "Vybrat tituly",
    "Planned": "Plánuji",
    "Plugins": "Pluginy",
    "Plugins you install show up here.": "Nainstalované pluginy se zobrazí tady.",
    "Poster": "Plakát",
    "Poster URL": "URL plakátu",
    "Posters: %lld": "Plakátů: %lld",
    "Privacy policy": "Zásady ochrany soukromí",
    "Progress": "Postup",
    "Rating": "Hodnocení",
    "Ratings": "Hodnocení",
    "Refresh details from TMDb": "Obnovit podrobnosti z TMDb",
    "Refresh details from TMDb?": "Obnovit podrobnosti z TMDb?",
    "Refreshing from TMDb": "Obnovuji z TMDb",
    "Release year": "Rok vydání",
    "Reload": "Znovu načíst",
    "Remove": "Odebrat",
    "Remove from favorites": "Odebrat z oblíbených",
    "Remove from this collection": "Odebrat z této kolekce",
    "Remove from this device": "Odstranit ze zařízení",
    "Remove photo": "Odebrat fotku",
    "Reorder": "Změnit pořadí",
    "Replace everything": "Nahradit vše",
    "Replace photo": "Nahradit fotku",
    "Reply to": "Odpověď na",
    "Report a problem": "Nahlásit problém",
    "Reset all": "Vynulovat vše",
    "Reset progress": "Resetovat průběh",
    "Reset the whole show": "Resetovat celý seriál",
    "Reset this episode": "Resetovat tento díl",
    "Reset this season": "Resetovat tuto sérii",
    "Resetting a season or the whole show also clears the episodes you've marked watched.": "Resetem série nebo celého seriálu se smažou i díly, které jste označili jako zhlédnuté.",
    "Results from every source you turn on are listed together when you add a title.": "Výsledky ze všech zapnutých zdrojů se při přidávání titulu zobrazí společně.",
    "Resumed at %@": "Pokračuje od %@",
    "Runtime": "Délka",
    "Runtime (minutes)": "Délka (minuty)",
    "Save": "Uložit",
    "Screenshots": "Snímky obrazovky",
    "Search collections": "Hledat kolekce",
    "Search or create": "Hledat nebo vytvořit",
    "Search sources": "Zdroje vyhledávání",
    "Search titles": "Hledat tituly",
    "Search titles and collections": "Hledat tituly a kolekce",
    "Searching TMDb needs a free API key from themoviedb.org.": "Hledání na TMDb potřebuje bezplatný klíč k API z themoviedb.org.",
    "Season %lld": "Série %lld",
    "Seasons": "Série",
    "Send": "Odeslat",
    "Send anonymously": "Odeslat anonymně",
    "Sent": "Odesláno",
    "Settings": "Nastavení",
    "Shake to report": "Zatřesením nahlásit",
    "Show": "Seriál",
    "Shows": "Seriály",
    "Sign in to Nucleus ID": "Přihlásit se k Nucleus ID",
    "Sign in with Nucleus ID": "Přihlásit se přes Nucleus ID",
    "Sign in with Nucleus ID to keep all your devices in step.": "Přihlaste se přes Nucleus ID a všechna vaše zařízení budou v souladu.",
    "Sign out": "Odhlásit se",
    "Sign out?": "Odhlásit se?",
    "Sign-in failed: %@": "Přihlášení selhalo: %@",
    "Small posters": "Malé plakáty",
    "Sort": "Řazení",
    "Sort by": "Řadit podle",
    "Start": "Začít",
    "Start clean": "Začít načisto",
    "Statistics": "Statistiky",
    "Status": "Stav",
    "Steps, what you expected, what you saw": "Kroky, co jste čekali a co se stalo",
    "Stop": "Zastavit",
    "Sync now": "Synchronizovat",
    "Sync with Nucleus ID": "Synchronizovat přes Nucleus ID",
    "Sync your watchlist across your devices with a free Nucleus ID.": "Synchronizujte watchlist mezi svými zařízeními s bezplatným Nucleus ID.",
    "Synced %@": "Synchronizováno %@",
    "Syncing…": "Synchronizuji…",
    "System": "Systém",
    "TMDb %@": "TMDb %@",
    "TMDb API key": "Klíč k TMDb API",
    "TMDb answered %lld.": "TMDb odpověděla %lld.",
    "TMDb rates it %@.": "TMDb hodnotí %@.",
    "Take photo": "Vyfotit",
    "Thanks for letting us know.": "Díky, že jste nám dali vědět.",
    "Thanks. We'll get back to you.": "Díky. Ozveme se vám.",
    "That email doesn't look right.": "Tenhle e-mail nevypadá správně.",
    "That file isn't a Watchlist backup.": "Tento soubor není záloha Watchlistu.",
    "The titles stay on your watchlist.": "Tituly zůstanou ve watchlistu.",
    "This can't be undone.": "Tohle nejde vzít zpět.",
    "This product uses the TMDB API but is not endorsed or certified by TMDB.": "Tento produkt používá TMDB API, ale není TMDB podporován ani certifikován.",
    "Title": "Název",
    "Title format": "Formát názvu",
    "Title not found": "Titul nenalezen",
    "Title, or search": "Název, nebo hledat",
    "Title, or search TMDb": "Název, nebo hledat na TMDb",
    "Titles": "Tituly",
    "Too large to sync. Remove some custom images.": "Příliš velké pro synchronizaci. Odeberte některé vlastní obrázky.",
    "Too many reports. Try again later.": "Příliš mnoho hlášení. Zkuste to později.",
    "Top years": "Nejčastější roky",
    "Total": "Celkem",
    "Total runtime (minutes)": "Celková délka (minuty)",
    "Track episodes": "Sledovat díly",
    "Try again": "Zkusit znovu",
    "Turning a plugin off hides what it adds. Nothing it saved is deleted.": "Vypnutím pluginu se skryje to, co přidává. Nic, co uložil, se nesmaže.",
    "Undo": "Zpět",
    "Up to 4.": "Nejvýš 4.",
    "Updated %lld. %lld not found on TMDb.": "Aktualizováno %lld. Na TMDb nenalezeno %lld.",
    "Use": "Použít",
    "Use {title} and {year} in the link.": "V odkazu použijte {title} a {year}.",
    "Use {title} and {year}. The Matrix (1999) opens %@": "Použijte {title} a {year}. Matrix (1999) otevře %@",
    "Version": "Verze",
    "Version %@": "Verze %@",
    "Version %@ is out. Update the app to get it.": "Je venku verze %@. Aktualizujte aplikaci.",
    "Watched": "Zhlédnuto",
    "Watching": "Sleduji",
    "Watchlist": "Watchlist",
    "Weekend picks": "Na víkend",
    "What happened?": "Co se stalo?",
    "Where to watch": "Kde sledovat",
    "Where “Open” takes this title. Default uses the choice in Settings.": "Kam vede „Otevřít“ u tohoto titulu. Výchozí použije volbu z Nastavení.",
    "Year": "Rok",
    "You can add more later.": "Další můžete přidat později.",
    "You were signed out. Sign in again to keep syncing.": "Byli jste odhlášeni. Přihlaste se znovu, ať se dál synchronizuje.",
    "You're offline. Try again when you're connected.": "Jste offline. Zkuste to znovu po připojení.",
    "Your rating": "Vaše hodnocení",
    "Your watchlist is empty.": "Váš watchlist je prázdný.",
    "Your watchlist stays in your Nucleus ID account either way.": "Watchlist vám v účtu Nucleus ID zůstane v každém případě.",
    "your link": "váš odkaz",
    "yours": "vaše",
}

# Strings with one count: key -> (English one, English other, Czech one, Czech few, Czech other).
PLURALS = {
    "%lld titles": ("%lld title", "%lld titles", "%lld titul", "%lld tituly", "%lld titulů"),
    "%lld seasons": ("%lld season", "%lld seasons", "%lld série", "%lld série", "%lld sérií"),
    "%lld ep": ("%lld ep", "%lld ep", "%lld díl", "%lld díly", "%lld dílů"),
    "%lld titles left": ("%lld title left", "%lld titles left", "zbývá %lld titul", "zbývají %lld tituly", "zbývá %lld titulů"),
    "Refresh %lld titles": ("Refresh %lld title", "Refresh %lld titles", "Obnovit %lld titul", "Obnovit %lld tituly", "Obnovit %lld titulů"),
    "Imported %lld titles.": ("Imported %lld title.", "Imported %lld titles.", "Importován %lld titul.", "Importovány %lld tituly.", "Importováno %lld titulů."),
    "Add %lld": ("Add %lld", "Add %lld", "Přidat %lld", "Přidat %lld", "Přidat %lld"),
    "Added %lld": ("Added %lld", "Added %lld", "Přidán %lld", "Přidány %lld", "Přidáno %lld"),
    "%lld of %lld episodes": None,  # two counts, see MULTI
}

TITLES = ("%arg title", "%arg titles", "%arg titul", "%arg tituly", "%arg titulů")
COLLECTIONS = ("%arg collection", "%arg collections", "%arg kolekce", "%arg kolekce", "%arg kolekcí")
EPISODES = ("%arg episode", "%arg episodes", "%arg dílu", "%arg dílů", "%arg dílů")

# Strings with several counts: key -> (English template, Czech template, [(name, forms), ...]).
MULTI = {
    "%lld titles and %lld collections on this device.": (
        "%#@a@ and %#@b@ on this device.", "V zařízení je %#@a@ a %#@b@.", [("a", TITLES), ("b", COLLECTIONS)]),
    "%lld titles and %lld collections.": (
        "%#@a@ and %#@b@.", "%#@a@ a %#@b@.", [("a", TITLES), ("b", COLLECTIONS)]),
    "%lld titles · %lld watching · %lld watched": (
        "%#@a@ · %2$lld watching · %3$lld watched", "%#@a@ · sleduji %2$lld · zhlédnuto %3$lld", [("a", TITLES)]),
    "This device has %lld titles and %lld collections. Merge them into your account, or replace them with the account's copy?": (
        "This device has %#@a@ and %#@b@. Merge them into your account, or replace them with the account's copy?",
        "V zařízení je %#@a@ a %#@b@. Sloučit je s účtem, nebo je nahradit kopií z účtu?", [("a", TITLES), ("b", COLLECTIONS)]),
    "%lld of %lld episodes": (
        "%1$lld of %#@b@", "%1$lld z %#@b@", [("b", EPISODES)]),
}


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def plural(one, few, other):
    forms = {"one": unit(one), "other": unit(other)}
    if few is not None:
        forms["few"] = unit(few)
        forms["many"] = unit(other)
    return {"plural": forms}


def main():
    strings = {}
    for key, cs in CS.items():
        strings[key] = {"localizations": {"cs": unit(cs)}}
    for key, forms in PLURALS.items():
        if forms is None:
            continue
        en1, en_other, cs1, cs_few, cs_other = forms
        strings[key] = {"localizations": {
            "en": {"variations": plural(en1, None, en_other)},
            "cs": {"variations": plural(cs1, cs_few, cs_other)},
        }}
    for key, (en, cs, args) in MULTI.items():
        positions = [i + 1 for i, part in enumerate(key.split("%lld")[:-1])]
        def subs(lang):
            out = {}
            for n, (name, f) in enumerate(args):
                arg = positions[["a", "b", "c"].index(name)] if name in "abc" else n + 1
                one, other, few = (f[0], f[1], None) if lang == "en" else (f[2], f[4], f[3])
                out[name] = {
                    "argNum": arg, "formatSpecifier": "lld",
                    "variations": plural(one.replace("%arg", "%arg"), few, other),
                }
            return out
        strings[key] = {"localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}, "substitutions": subs("en")},
            "cs": {"stringUnit": {"state": "translated", "value": cs}, "substitutions": subs("cs")},
        }}
    # Merge into what Xcode keeps there (its own entries and bookkeeping), replacing only our translations.
    existing = json.loads(CATALOG.read_text()) if CATALOG.exists() else {}
    merged = existing.get("strings", {})
    for key, entry in strings.items():
        merged[key] = {**merged.get(key, {}), **entry}
    catalog = {**existing, "sourceLanguage": "en", "strings": dict(sorted(merged.items())), "version": existing.get("version", "1.0")}
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, separators=(",", " : "), sort_keys=True) + "\n")
    print(f"{len(strings)} strings → {CATALOG.relative_to(Path.cwd()) if CATALOG.is_relative_to(Path.cwd()) else CATALOG}")


if __name__ == "__main__":
    main()
