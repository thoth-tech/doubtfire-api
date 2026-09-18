FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 AS texlive-builder

ARG TL_MIRROR="https://texlive.info/historic/systems/texlive/2025/tlnet-final"
ARG TL_INSTALLER_SHA512="a307d7d11bcbd1f054ad0b0d476f7f12bc1a40d07445020edef8713b44453831d18a2f1722c3d2b0ea2e4fe6c06183a79d1c4049495113f412a9f5a570a8614d"

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  perl \
  curl \
  wget \
  ca-certificates \
  xz-utils && \
  rm -rf /var/lib/apt/lists/* && \
  mkdir /tmp/texlive && cd /tmp/texlive && \
  wget --https-only "$TL_MIRROR/install-tl-unx.tar.gz" && \
  echo "$TL_INSTALLER_SHA512  install-tl-unx.tar.gz" | sha512sum --check - && \
  tar xzvf ./install-tl-unx.tar.gz && \
  ( \
  echo "selected_scheme scheme-basic" && \
  echo "instopt_adjustpath 0" && \
  echo "tlpdbopt_install_docfiles 0" && \
  echo "tlpdbopt_install_srcfiles 0" && \
  echo "TEXDIR /opt/texlive/" && \
  echo "TEXMFLOCAL /opt/texlive/texmf-local" && \
  echo "TEXMFSYSCONFIG /opt/texlive/texmf-config" && \
  echo "TEXMFSYSVAR /opt/texlive/texmf-var" && \
  echo "TEXMFHOME ~/.texmf" \
  ) > /tmp/texlive.profile && \
  ./install-tl-*/install-tl --location "$TL_MIRROR" -profile /tmp/texlive.profile && \
  rm -rf /tmp/*


ENV PATH=$PATH:/opt/texlive/bin/x86_64-linux:/opt/texlive/bin/aarch64-linux

# Install required TeX Live packages for lualatex compilation. Keep the frozen
# repository explicit here as well as in install-tl so a local tlmgr setting
# cannot make this second phase mutable.
RUN tlmgr --repository "$TL_MIRROR" install \
  catchfile \
  csvsimple \
  environ \
  fontawesome \
  fontspec \
  framed \
  fvextra \
  lastpage \
  lineno \
  luacode \
  luaotfload \
  luatexbase \
  luatextra \
  markdown \
  metalogo \
  minted \
  multirow \
  newpax \
  paralist \
  pdfcol \
  pdflscape \
  pdfmanagement-testphase \
  pdfpages \
  tagpdf \
  tcolorbox \
  tikzfill \
  upquote \
  xstring \
  enumitem

# Final image
FROM debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241


RUN apt-get update && apt-get install -y --no-install-recommends \
  imagemagick \
  python3-pygments \
  librsvg2-bin && \
  rm -rf /var/lib/apt/lists/*

# Copy only the installed TeX Live binaries and files (excludes build tools like curl, wget)
COPY --from=texlive-builder /opt/texlive /opt/texlive

ENV PATH=$PATH:/opt/texlive/bin/x86_64-linux:/opt/texlive/bin/aarch64-linux

# Preload fonts
RUN luaotfload-tool --update

# Exercise the same PDF-management ordering used by application.pdf.erbtex in
# the final image. This proves the separately installed implementation and its
# Hyperref integration survived the builder-to-runtime copy.
RUN kpsewhich pdfmanagement-testphase.sty && \
  lualatex --halt-on-error --interaction=nonstopmode \
    --jobname=pdfmanagement-smoke --output-directory=/tmp \
    '\DocumentMetadata{uncompress}\documentclass{article}\usepackage[colorlinks]{hyperref}\begin{document}OnTrack smoke. \href{https://example.invalid}{link}\end{document}' && \
  test -s /tmp/pdfmanagement-smoke.pdf && \
  rm -f /tmp/pdfmanagement-smoke.*

# Copy in Latex build script, along with asset images
COPY ./lib/shell/latex_build.sh /texlive/shell/latex_build.sh
COPY ./public/assets/images /doubtfire/public/assets/images

RUN chmod +x /texlive/shell/latex_build.sh

CMD ["sh", "-c", "sleep infinity"]
