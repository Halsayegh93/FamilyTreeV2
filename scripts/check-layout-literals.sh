#!/bin/zsh
# حارس المسافات والأحجام (جولة ٢٠٢٦-١١-١١): يعدّ الأرقام الثابتة في Views/ و Components/ خارج أسماء نظام التصميم
# (DS.Page / DS.Card / DSBox / DS.Spacing / DS.Icon / DS.Radius). لا يُربط بالبناء — شغّله قبل الدمج:
#   scripts/check-layout-literals.sh          ← العدّ لكل ملف
#   scripts/check-layout-literals.sh lines    ← السطور نفسها
# المستثنى: رسوم بطاقات المناسبات، هندسة الشجرة، المجسّمات والرسوم، وملفات نظام التصميم نفسها.
cd "$(dirname "$0")/../FamilyTreeV2/FamilyTreeV2" || exit 1
PAT='\.padding\(([^)]*,\s*)?-?[1-9][0-9]*(\.[0-9]+)?\)|spacing: -?[1-9][0-9]*(\.[0-9]+)?[,)]|\.frame\(((min|max)?(W|w)idth|(min|max)?(H|h)eight): [1-9][0-9]*[,)]|\.font\(\.system\(size: [0-9]+|cornerRadius: [1-9][0-9]*(\.[0-9]+)?[,)]|DS\.Spacing\.[a-z]+ ?[+-] ?[0-9]'
ALLOW='OccasionPostView|OccasionModel[0-9]View|OccasionLegacyKit|OccasionKit|FT5S|FT3D|FTTileScenes|ArtTrial|Moments|TreeArt|MemberNodeView|AppGuideBox|DesignSystem\.swift'
FILES=$(find Views Components -name '*.swift' | grep -vE "$ALLOW")
total=0
for f in ${=FILES}; do
  n=$(grep -cE "$PAT" "$f")
  if [ "$n" -gt 0 ]; then
    total=$((total + n))
    if [ "$1" = lines ]; then grep -nE "$PAT" "$f" | sed "s|^|$f:|" | cut -c1-200; else echo "$n $f"; fi
  fi
done | sort -rn
for f in ${=FILES}; do n=$(grep -cE "$PAT" "$f"); total=$((total + n)); done
echo "المجموع: $total"
