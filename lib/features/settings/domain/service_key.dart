import 'package:flutter/material.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/truenas/domain/truenas_version.dart';

enum ServiceKey {
  seerr,
  radarr,
  sonarr,
  lidarr,
  qbittorrent,
  transmission,
  bazarr,
  truenas,
  dockge,
  prowlarr,
  readarr,
  sabnzbd,
  nzbget,
  unraid,
  nginxProxyManager,
  jellyfin,
  plex,
}

/// High-level grouping used to organise services across the app.
///
/// Cupola started as a media companion but is growing into a homelab hub, so
/// services are grouped by the kind of job they do. This enum is the single
/// source of truth for that grouping — the Home dashboard, Settings and the
/// onboarding flow all read from it, so a new service only needs a [domain]
/// assignment in one place.
enum ServiceDomain {
  media(label: 'Media'),
  downloads(label: 'Downloads'),

  /// Media servers — the only services in the app that know about *people*.
  ///
  /// Every other domain answers questions about objects: is this film owned,
  /// grabbed, subtitled, on disk. A media server is the only source of
  /// subject-and-time state — who is watching, where they stopped, what is next
  /// for them, what nobody has played. That is why this is its own domain and
  /// not more Media, and it is the guard against re-rendering Radarr's library
  /// under a second name.
  ///
  /// Ordered between [downloads] and [infrastructure] deliberately: the bands
  /// then read as the pipeline they are — catalogue, acquire, watch, and the box
  /// it all runs on.
  stream(label: 'Stream'),
  infrastructure(label: 'Infrastructure');

  const ServiceDomain({required this.label});

  final String label;

  /// The configured services belonging to this domain, in declaration order.
  List<ServiceKey> get services =>
      ServiceKey.values.where((s) => s.domain == this).toList(growable: false);
}

extension ServiceKeyExtension on ServiceKey {
  /// Which [ServiceDomain] this service belongs to. See [ServiceDomain].
  ServiceDomain get domain {
    switch (this) {
      case ServiceKey.seerr:
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.bazarr:
      case ServiceKey.readarr:
        return ServiceDomain.media;
      case ServiceKey.qbittorrent:
      case ServiceKey.transmission:
      case ServiceKey.prowlarr:
      case ServiceKey.sabnzbd:
      case ServiceKey.nzbget:
        return ServiceDomain.downloads;
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return ServiceDomain.stream;
      case ServiceKey.truenas:
      case ServiceKey.dockge:
      case ServiceKey.unraid:
      // A reverse proxy is not a download client that happens to run on the
      // box: it is the box's front door. Every other service in the app is
      // usually reached *through* it, which is exactly why it belongs beside
      // the NAS and the container manager rather than anywhere else.
      case ServiceKey.nginxProxyManager:
        return ServiceDomain.infrastructure;
    }
  }

  /// Whether tapping this service opens a full multi-screen console (with its
  /// own inner navigation) rather than a single detail screen. Heavy services
  /// like TrueNAS and Dockge are effectively sub-apps.
  bool get isFullConsole =>
      this == ServiceKey.truenas || this == ServiceKey.dockge;

  String get title {
    switch (this) {
      case ServiceKey.seerr:
        return 'Seerr';
      case ServiceKey.radarr:
        return 'Radarr';
      case ServiceKey.sonarr:
        return 'Sonarr';
      case ServiceKey.lidarr:
        return 'Lidarr';
      case ServiceKey.qbittorrent:
        return 'qBittorrent';
      case ServiceKey.transmission:
        return 'Transmission';
      case ServiceKey.nginxProxyManager:
        return 'Nginx Proxy Manager';
      case ServiceKey.bazarr:
        return 'Bazarr';
      case ServiceKey.truenas:
        return 'TrueNAS';
      case ServiceKey.dockge:
        return 'Dockge';
      case ServiceKey.prowlarr:
        return 'Prowlarr';
      case ServiceKey.readarr:
        return 'Readarr';
      case ServiceKey.sabnzbd:
        return 'SABnzbd';
      case ServiceKey.nzbget:
        return 'NZBGet';
      case ServiceKey.unraid:
        return 'Unraid';
      case ServiceKey.jellyfin:
        return 'Jellyfin';
      case ServiceKey.plex:
        return 'Plex';
    }
  }

  /// The name to use where a cell is too narrow to spell the full [title].
  ///
  /// Defaults to [title], because for fourteen of the sixteen services there is
  /// nothing to shorten — this exists for the one name that does not fit the
  /// folded matrix cell, which clips at one line with an ellipsis. "NPM" is
  /// deliberately *not* the abbreviation used: on a developer's own homelab
  /// that string already means npm the package manager, and a three-letter
  /// label that resolves to the wrong tool is worse than a longer one that
  /// resolves to the right one.
  String get shortTitle =>
      this == ServiceKey.nginxProxyManager ? 'Proxy Manager' : title;

  IconData get icon {
    switch (this) {
      case ServiceKey.seerr:
        return Icons.search_rounded;
      case ServiceKey.radarr:
        return Icons.movie_rounded;
      case ServiceKey.sonarr:
        return Icons.tv_rounded;
      case ServiceKey.lidarr:
        return Icons.music_note_rounded;
      case ServiceKey.qbittorrent:
        return Icons.download_rounded;
      // Told apart from the three download clients by *direction*, not detail:
      // theirs are all one-way arrows into the box, and a BitTorrent daemon is
      // the one client in the group that is equally busy sending. The paired
      // arrows survive the 18pt matrix glyph where a restyled download arrow
      // would read as a second qBittorrent.
      case ServiceKey.transmission:
        return Icons.swap_vert_rounded;
      // A reverse proxy is a fork in the road — one address in, many services
      // out. Distinct at glyph size from TrueNAS's drive stack, Dockge's
      // layers and Unraid's board.
      case ServiceKey.nginxProxyManager:
        return Icons.alt_route_rounded;
      case ServiceKey.bazarr:
        return Icons.subtitles_rounded;
      case ServiceKey.truenas:
        return Icons.storage_rounded;
      case ServiceKey.dockge:
        return Icons.layers_rounded;
      case ServiceKey.prowlarr:
        return Icons.travel_explore_rounded;
      case ServiceKey.readarr:
        return Icons.menu_book_rounded;
      case ServiceKey.sabnzbd:
        return Icons.cloud_download_rounded;
      case ServiceKey.nzbget:
        return Icons.cloud_sync_rounded;
      case ServiceKey.unraid:
        return Icons.developer_board_rounded;
      // The two media servers do the same job, so they are told apart by
      // *silhouette* rather than by detail: a circle against a rounded
      // rectangle survives the 18pt glyph on an expanded matrix cell and the
      // 32pt one on a folded card, where two screen-shaped glyphs would not.
      // Neither may be `live_tv_rounded` — that is a TV outline with signal
      // arcs and collides with Sonarr's `tv_rounded` at cell size.
      case ServiceKey.jellyfin:
        return Icons.play_circle_rounded;
      case ServiceKey.plex:
        return Icons.smart_display_rounded;
    }
  }

  Color get accent {
    switch (this) {
      case ServiceKey.seerr:
        return AppColors.seerr;
      case ServiceKey.radarr:
        return AppColors.radarr;
      case ServiceKey.sonarr:
        return AppColors.sonarr;
      case ServiceKey.lidarr:
        return AppColors.lidarr;
      case ServiceKey.qbittorrent:
        return AppColors.qbittorrent;
      case ServiceKey.transmission:
        return AppColors.transmission;
      case ServiceKey.nginxProxyManager:
        return AppColors.nginxProxyManager;
      case ServiceKey.bazarr:
        return AppColors.bazarr;
      case ServiceKey.truenas:
        return AppColors.truenas;
      case ServiceKey.dockge:
        return AppColors.dockge;
      case ServiceKey.prowlarr:
        return AppColors.prowlarr;
      case ServiceKey.readarr:
        return AppColors.readarr;
      case ServiceKey.sabnzbd:
        return AppColors.sabnzbd;
      case ServiceKey.nzbget:
        return AppColors.nzbget;
      case ServiceKey.unraid:
        return AppColors.unraid;
      case ServiceKey.jellyfin:
        return AppColors.jellyfin;
      case ServiceKey.plex:
        return AppColors.plex;
    }
  }

  /// Whether this service authenticates with a single API key rather than a
  /// username and password.
  ///
  /// **The one place the app decides that.** Persistence, the settings form and
  /// the verifier all read this rather than re-deriving "is it one of these
  /// three" — the three-way check used to be spelled out in five files, so the
  /// next credential-authenticated service could be added to four of them and
  /// leave storage and the UI disagreeing about which fields even exist.
  ///
  /// Written as an exhaustive `switch` on purpose: a `!=` chain would silently
  /// class a newly added service as API-key authenticated, whereas this makes
  /// the compiler ask.
  bool get usesApiKey {
    switch (this) {
      case ServiceKey.qbittorrent:
      case ServiceKey.dockge:
      case ServiceKey.nzbget:
      // HTTP Basic, straight from `rpc-username`/`rpc-password`. Transmission
      // mints no key of any kind.
      case ServiceKey.transmission:
      // Nginx Proxy Manager has **no long-lived API key at all**: the only
      // credential it accepts is the account's own email and password, which
      // `POST /api/tokens` exchanges for a short-lived bearer token. That is a
      // property of the server, not a shortcut taken here — see [setupNote]
      // for what it means for the user.
      case ServiceKey.nginxProxyManager:
        return false;
      case ServiceKey.seerr:
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.bazarr:
      case ServiceKey.truenas:
      case ServiceKey.prowlarr:
      case ServiceKey.readarr:
      case ServiceKey.sabnzbd:
      case ServiceKey.unraid:
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return true;
    }
  }

  /// Whether the library this service serves has to be entered through a chosen
  /// person, so the settings screen offers a viewer picker once it connects.
  ///
  /// True for Jellyfin alone, and structurally rather than by preference: a
  /// Jellyfin API key authenticates as an administrator with **no user
  /// attached**, so every user-scoped question (resume positions, next up,
  /// unplayed) needs a `userId` supplied explicitly. Plex is excluded because
  /// its token *is* its user and `/library/*` accepts no impersonation
  /// parameter — a Plex library has exactly one perspective. Expressed as a
  /// capability so the shared settings screen inserts the control the same way
  /// it decides on `SearchHeadroomCard.appliesTo`, rather than naming a
  /// `ServiceKey` inline.
  bool get needsViewerSelection => this == ServiceKey.jellyfin;

  /// The port this service listens on out of the box.
  ///
  /// Offered as a one-tap suggestion next to the address field, alongside the
  /// host carried over from the service configured before it — on a home lab one
  /// box usually runs everything on different ports, so between the two most
  /// services become a tap plus a pasted key. A suggestion only: a service
  /// behind a reverse proxy is reached on 443 with a path, and nothing here
  /// overwrites an address the user has already typed.
  int get defaultPort {
    switch (this) {
      case ServiceKey.seerr:
        return 5055;
      case ServiceKey.radarr:
        return 7878;
      case ServiceKey.sonarr:
        return 8989;
      case ServiceKey.lidarr:
        return 8686;
      case ServiceKey.readarr:
        return 8787;
      case ServiceKey.prowlarr:
        return 9696;
      case ServiceKey.bazarr:
        return 6767;
      case ServiceKey.qbittorrent:
      case ServiceKey.sabnzbd:
        return 8080;
      case ServiceKey.nzbget:
        return 6789;
      case ServiceKey.transmission:
        return 9091;
      // 81, not 80 or 443. Those two are the proxy *doing its job* — the
      // hostnames it fronts. The admin interface, which is the only thing
      // carrying an API, listens separately.
      case ServiceKey.nginxProxyManager:
        return 81;
      case ServiceKey.jellyfin:
        return 8096;
      case ServiceKey.plex:
        return 32400;
      case ServiceKey.dockge:
        return 5001;
      // Both ship a TLS web UI on the standard port.
      case ServiceKey.truenas:
      case ServiceKey.unraid:
        return 443;
    }
  }

  /// What the credential is called in this service's own vocabulary.
  ///
  /// Plex calls its own credential a token, and the field has said so since the
  /// integration shipped; everything else keeps the wording the settings form
  /// already used, so moving the string into the registry changes where it lives
  /// and not what it says.
  String get credentialLabel =>
      this == ServiceKey.plex ? 'Plex token' : 'API Key';

  /// What the *non-secret* half of a credential pair is called.
  ///
  /// The sibling of [credentialLabel], and it exists for one service: Nginx
  /// Proxy Manager authenticates on an account's **email**, and its
  /// `POST /api/tokens` rejects a bare username outright. Labelling that field
  /// "Username" would be an invitation to fail the login and then blame the
  /// password. Every other credential service really does want a username.
  String get usernameLabel =>
      this == ServiceKey.nginxProxyManager ? 'Email' : 'Username';

  /// Where the credential lives inside *this service's* own interface.
  ///
  /// A breadcrumb rather than prose, shown under the field it explains. Null for
  /// the services that authenticate with the web-UI login the user already
  /// knows, since there is nothing to go and find.
  String? get credentialPath {
    switch (this) {
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.readarr:
      case ServiceKey.prowlarr:
      case ServiceKey.bazarr:
      case ServiceKey.seerr:
        return 'Settings → General → API Key';
      case ServiceKey.sabnzbd:
        return 'Config → General → API Key';
      case ServiceKey.jellyfin:
        return 'Dashboard → Advanced → API Keys';
      case ServiceKey.truenas:
        return 'Credentials → API Keys';
      case ServiceKey.unraid:
        return 'Settings → Management Access → Developer Options';
      case ServiceKey.plex:
        return 'any item → Get Info → View XML → copy X-Plex-Token';
      // Web-UI login: the user already has these.
      case ServiceKey.qbittorrent:
      case ServiceKey.dockge:
      case ServiceKey.nzbget:
      case ServiceKey.transmission:
      case ServiceKey.nginxProxyManager:
        return null;
    }
  }

  /// Setup guidance shown above the address field, for the services where the
  /// API needs turning on first or the project itself carries a caveat worth
  /// stating before anything is typed.
  ///
  /// Registry data rather than an if-chain inside the shared settings screen,
  /// for the same reason [credentialLabel], [credentialPath] and [defaultPort]
  /// live here: everything a service *says about itself* belongs next to the
  /// rest of its description, so adding a service is one entry rather than a
  /// hunt through the screens that render it. Null for the majority, which need
  /// nothing said.
  String? get setupNote {
    switch (this) {
      case ServiceKey.truenas:
        return 'Requires TrueNAS SCALE $kTrueNasMinVersion or newer. Create an '
            'API key under Credentials → Local Users, and use the https:// '
            'address of the web UI.';
      case ServiceKey.unraid:
        return 'Enable the Unraid API first: Settings → Management Access → '
            'Developer Options → turn on the GraphQL sandbox, then create an '
            'API key under API Keys. Without this the endpoint will not '
            'respond.';
      // Readarr development stopped upstream. Saying so here is the honest
      // thing: the integration works against the last released API, but the
      // user should know they are pointing at a project that will not receive
      // fixes.
      case ServiceKey.readarr:
        return 'Readarr development has stopped upstream. Cupola targets its '
            'last released API, so existing instances keep working, but expect '
            'no new server-side fixes.';
      case ServiceKey.jellyfin:
        return 'Create an API key under Dashboard → Advanced → API Keys. The '
            'key authenticates as an administrator but carries no user of its '
            'own, so pick whose watch state to read below once the connection '
            'works.';
      // Naming the *kind* of token matters more than naming the place. Plex has
      // two, and the modern one is a dead end here: a JWT expires after seven
      // days and can only be refreshed through plex.tv, which Cupola never
      // calls. Saying so up front beats a week of working software.
      case ServiceKey.plex:
        return 'Open any item in Plex Web, choose Get Info → View XML, and copy '
            'the X-Plex-Token from the address bar. Cupola never contacts '
            'plex.tv, so it needs a long-lived device token — not a temporary '
            'one beginning "eyJ".';
      // The single most common reason a Transmission daemon is reachable in a
      // browser and not from a phone, and it is worth saying before the address
      // is typed rather than after a mystifying 403.
      case ServiceKey.transmission:
        return 'Use the same username and password the Transmission web '
            'interface asks for, and check that this device is allowed: '
            '`rpc-whitelist` defaults to 127.0.0.1 only, so a phone on the same '
            'network is refused until the range is widened. Note that '
            'Transmission has one all-or-nothing credential and it can set the '
            'script it runs when a download finishes — treat it as a login to '
            'the machine itself, and do not reuse a password from anywhere '
            'else.';
      // Says the uncomfortable thing plainly, because the user cannot choose
      // otherwise and deserves to know what they are handing over.
      case ServiceKey.nginxProxyManager:
        return 'Nginx Proxy Manager issues no API key — the only credential it '
            'accepts is an account login, which Cupola exchanges for a '
            'short-lived token it keeps in memory and never writes to disk. '
            'Create a dedicated user for Cupola rather than using your admin '
            'account, and point this at the admin interface (port 81 by '
            'default), not at a hostname the proxy serves.';
      case ServiceKey.seerr:
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.qbittorrent:
      case ServiceKey.bazarr:
      case ServiceKey.dockge:
      case ServiceKey.prowlarr:
      case ServiceKey.sabnzbd:
      case ServiceKey.nzbget:
        return null;
    }
  }

  /// Whether the global search tab fans out to this service.
  ///
  /// **Jellyfin and Plex are deliberately excluded, and this is a design
  /// decision rather than an omission.** Adding them would make the same film
  /// return in up to six sections: Radarr and Sonarr "search" is `movie/lookup`
  /// and `series/lookup` — a TMDB/TVDB lookup, not a library search — so "Dune"
  /// already produces four groups, in `Future.wait` declaration order with no
  /// relevance ranking, and `_SearchSection` renders every group including the
  /// empty ones. A Stream match is worth strictly more as a *decoration* on the
  /// Radarr/Sonarr/Seerr row that is already there — "On Jellyfin · 34 min in" —
  /// joined on `tmdbId`, which is the same move `arrMediaExtrasSlots` already
  /// makes for Seerr data inside an arr screen.
  bool get isSearchable {
    return this == ServiceKey.seerr ||
        this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr ||
        this == ServiceKey.bazarr;
  }

  bool get supportsManualImport {
    return this == ServiceKey.radarr ||
        this == ServiceKey.sonarr ||
        this == ServiceKey.lidarr;
  }

  String get apiVersion {
    switch (this) {
      case ServiceKey.seerr:
      case ServiceKey.lidarr:
      case ServiceKey.readarr:
        return 'v1';
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
        return 'v3';
      case ServiceKey.qbittorrent:
        return 'WebUI';
      case ServiceKey.transmission:
        return 'RPC';
      case ServiceKey.nginxProxyManager:
        return 'API';
      case ServiceKey.bazarr:
        return 'v1';
      case ServiceKey.truenas:
        return 'v25';
      case ServiceKey.dockge:
        return 'Socket.IO';
      case ServiceKey.prowlarr:
        return 'v1';
      case ServiceKey.sabnzbd:
        return 'API';
      case ServiceKey.nzbget:
        return 'JSON-RPC';
      case ServiceKey.unraid:
        return 'GraphQL';
      case ServiceKey.jellyfin:
        return 'v10';
      case ServiceKey.plex:
        return 'v1';
    }
  }

  String get itemLabel {
    switch (this) {
      case ServiceKey.seerr:
        return 'requests';
      case ServiceKey.radarr:
        return 'movies';
      case ServiceKey.sonarr:
        return 'series';
      case ServiceKey.lidarr:
        return 'artists';
      case ServiceKey.qbittorrent:
      case ServiceKey.transmission:
        return 'torrents';
      // The hostnames it fronts. Not "hosts" on its own — a homelab already
      // calls the physical boxes that, and this counts neither of them.
      case ServiceKey.nginxProxyManager:
        return 'proxy hosts';
      case ServiceKey.bazarr:
        return 'subtitles';
      case ServiceKey.truenas:
        return 'pools';
      case ServiceKey.dockge:
        return 'stacks';
      case ServiceKey.prowlarr:
        return 'indexers';
      case ServiceKey.readarr:
        return 'authors';
      case ServiceKey.sabnzbd:
        return 'downloads';
      case ServiceKey.nzbget:
        return 'downloads';
      case ServiceKey.unraid:
        return 'containers';
      // The top-level thing you enumerate on a media server. Not "movies" —
      // a single Jellyfin or Plex instance mixes films, shows and music, and
      // naming one of them would both misdescribe the server and read as a
      // duplicate of Radarr's or Sonarr's own label.
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return 'libraries';
    }
  }

  String get routeParam {
    switch (this) {
      case ServiceKey.seerr:
        return 'seerr';
      // The only service whose enum name is camelCase, and a URL is the one
      // place that shows. Every other route segment is the lowercase name the
      // user would type, so this one is spelled out rather than derived.
      case ServiceKey.nginxProxyManager:
        return 'npm';
      case ServiceKey.radarr:
      case ServiceKey.sonarr:
      case ServiceKey.lidarr:
      case ServiceKey.qbittorrent:
      case ServiceKey.transmission:
      case ServiceKey.bazarr:
      case ServiceKey.truenas:
      case ServiceKey.dockge:
      case ServiceKey.prowlarr:
      case ServiceKey.readarr:
      case ServiceKey.sabnzbd:
      case ServiceKey.nzbget:
      case ServiceKey.unraid:
      case ServiceKey.jellyfin:
      case ServiceKey.plex:
        return name;
    }
  }

  String? extractHost(String? url) {
    final value = url?.trim() ?? '';
    if (value.isEmpty) return null;
    final parseableValue = value.contains('://') ? value : 'http://$value';

    try {
      final uri = Uri.parse(parseableValue);
      if (uri.host.isNotEmpty) {
        return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
      }

      return uri.path.isEmpty ? null : uri.path;
    } catch (_) {
      return null;
    }
  }
}
