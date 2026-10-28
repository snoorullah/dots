"""A stable, pleasant name per Claude session: "Sirius", "Iris", "Danube".

A session id is a uuid nobody can say aloud. The name is a pure function of it
(sha256 -> index), so every process derives the same one with no registry and no state to
lose: the hook, the ingest cycle and `dots-jump <agent>` all agree.

256 words, so the index is one byte of the digest and the distribution is exactly flat.
Two sessions open at once collide 1 time in 256; the pane id still disambiguates them.
"""
import hashlib

STARS = """Sirius Vega Altair Rigel Deneb Antares Capella Arcturus Procyon Canopus Betelgeuse
Aldebaran Spica Regulus Polaris Castor Pollux Mizar Alcor Algol Fomalhaut Bellatrix Alnitak
Alnilam Mintaka Saiph Hadar Achernar Shaula Sargas Kochab Dubhe Merak Phecda Megrez Alioth
Alkaid Thuban Albireo Enif Markab Scheat Algenib Mirach Almach Hamal Menkar Diphda Nunki
Ascella Eltanin Sadr Gienah Zosma Denebola Alphard Alphecca Izar Mirfak Elnath Alhena Wezen
Adhara Mirzam Naos Avior Atria Alnair Suhail Acrux Gacrux Mimosa Ankaa Schedar Caph Ruchbah
Navi Segin""".split()

FLOWERS = """Aster Iris Lotus Peony Dahlia Camellia Jasmine Lavender Magnolia Orchid Poppy Tulip
Violet Zinnia Marigold Primrose Foxglove Hyacinth Lilac Daisy Azalea Begonia Clover Cosmos
Freesia Gardenia Heather Hibiscus Hydrangea Lupine Mallow Nigella Oleander Pansy Petunia
Phlox Protea Salvia Snowdrop Sorrel Thistle Verbena Wisteria Yarrow Anemone Bluebell
Buttercup Campion Chicory Columbine Cowslip Crocus Delphinium Edelweiss Forsythia Geranium
Gentian Honeysuckle Jonquil Larkspur Lobelia Myrtle Narcissus Nasturtium Periwinkle Quince
Rosemary Saffron Statice Tansy Trillium Veronica Waratah Amaryllis Alyssum Celosia Clematis
Coreopsis Dianthus Erica Fuchsia Gladiolus Hellebore""".split()

RIVERS = """Amazon Nile Danube Rhine Volga Ganges Indus Yangtze Mekong Niger Congo Zambezi Orinoco
Tigris Euphrates Jordan Seine Loire Rhone Thames Severn Tyne Tweed Shannon Elbe Oder Vistula
Dnieper Ural Lena Yenisei Amur Irrawaddy Salween Brahmaputra Godavari Krishna Kaveri Narmada
Yamuna Sutlej Jhelum Chenab Beas Oxus Murray Darling Yukon Mackenzie Columbia Colorado Hudson
Potomac Ohio Missouri Parana Uruguay Magdalena Essequibo Limpopo Okavango Volta Senegal
Tagus Douro Ebro Arno Tiber Adige Drava Sava Tisza Prut Neva Dvina Pechora Kama Irtysh
Tobol Don Avon Cam Isis Wye Dee Tay Spey Trent Mersey Humber Ouse Exe Tamar Fal Dart""".split()

NAMES = tuple(STARS + FLOWERS + RIVERS)
assert len(NAMES) == 256 == len(set(NAMES)), len(NAMES)


def for_session(sess):
    """The agent name for a session id. Empty or None gets a fixed name, never an error."""
    digest = hashlib.sha256(str(sess or "").encode("utf-8")).digest()
    return NAMES[digest[0]]
