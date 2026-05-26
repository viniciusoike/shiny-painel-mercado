pal <- c("#264653", "#287271", "#2A9D8F", "#8AB17D", "#E9C46A", "#EFB366",
         "#F4A261", "#EE8959", "#E76F51")

get_color_palette <- function(n) {
  if (n == 1) return(pal[1])
  if (n == 2) return(pal[c(1, 5)])
  if (n == 3) return(pal[c(1, 5, 9)])
  if (n == 4) return(pal[c(1, 3, 5, 9)])
  if (n == 5) return(pal[c(1, 3, 5, 7, 9)])
  pal
}
