(* Automatically generated from gui.glade.patched by lablgladecc *)

class window_MARIONNET ?(file="gui.glade.patched") ?domain ?autoconnect(*=true*) () =
  let xmldata = Glade.create ~file  ~root:"window_MARIONNET" ?domain () in
  object (self)
    inherit Glade.xml ?autoconnect xmldata
    val toplevel =
      new GWindow.window (GtkWindow.Window.cast
        (Glade.get_widget_msg ~name:"window_MARIONNET" ~info:"GtkWindow" xmldata))
    method toplevel = toplevel
    val window_MARIONNET =
      new GWindow.window (GtkWindow.Window.cast
        (Glade.get_widget_msg ~name:"window_MARIONNET" ~info:"GtkWindow" xmldata))
    method window_MARIONNET = window_MARIONNET
    val vbox1 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox1" ~info:"GtkVBox" xmldata))
    method vbox1 = vbox1
    val menubar_MARIONNET =
      new GMenu.menu_shell (GtkMenu.MenuBar.cast
        (Glade.get_widget_msg ~name:"menubar_MARIONNET" ~info:"GtkMenuBar" xmldata))
    method menubar_MARIONNET = menubar_MARIONNET
    val notebook_CENTRAL =
      new GPack.notebook (GtkPack.Notebook.cast
        (Glade.get_widget_msg ~name:"notebook_CENTRAL" ~info:"GtkNotebook" xmldata))
    method notebook_CENTRAL = notebook_CENTRAL
    val hbox1 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox1" ~info:"GtkHBox" xmldata))
    method hbox1 = hbox1
    val scrolledwindow2 =
      new GBin.scrolled_window (GtkBin.ScrolledWindow.cast
        (Glade.get_widget_msg ~name:"scrolledwindow2" ~info:"GtkScrolledWindow" xmldata))
    method scrolledwindow2 = scrolledwindow2
    val viewport2 =
      new GBin.viewport (GtkBin.Viewport.cast
        (Glade.get_widget_msg ~name:"viewport2" ~info:"GtkViewport" xmldata))
    method viewport2 = viewport2
    val hbox_COMPONENTS =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox_COMPONENTS" ~info:"GtkHBox" xmldata))
    method hbox_COMPONENTS = hbox_COMPONENTS
    val toolbar_COMPONENTS =
      new GButton.toolbar (GtkButton.Toolbar.cast
        (Glade.get_widget_msg ~name:"toolbar_COMPONENTS" ~info:"GtkToolbar" xmldata))
    method toolbar_COMPONENTS = toolbar_COMPONENTS
    val vseparator1 =
      new GObj.widget_full (GtkMisc.Separator.cast
        (Glade.get_widget_msg ~name:"vseparator1" ~info:"GtkVSeparator" xmldata))
    method vseparator1 = vseparator1
    val vbox3 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox3" ~info:"GtkVBox" xmldata))
    method vbox3 = vbox3
    val label_VIRTUAL_NETWORK =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_VIRTUAL_NETWORK" ~info:"GtkLabel" xmldata))
    method label_VIRTUAL_NETWORK = label_VIRTUAL_NETWORK
    val notebook_INTERNAL =
      new GPack.notebook (GtkPack.Notebook.cast
        (Glade.get_widget_msg ~name:"notebook_INTERNAL" ~info:"GtkNotebook" xmldata))
    method notebook_INTERNAL = notebook_INTERNAL
    val hbox31 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox31" ~info:"GtkHBox" xmldata))
    method hbox31 = hbox31
    val scrolledwindow1 =
      new GBin.scrolled_window (GtkBin.ScrolledWindow.cast
        (Glade.get_widget_msg ~name:"scrolledwindow1" ~info:"GtkScrolledWindow" xmldata))
    method scrolledwindow1 = scrolledwindow1
    val viewport1 =
      new GBin.viewport (GtkBin.Viewport.cast
        (Glade.get_widget_msg ~name:"viewport1" ~info:"GtkViewport" xmldata))
    method viewport1 = viewport1
    val sketch =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"sketch" ~info:"GtkImage" xmldata))
    method sketch = sketch
    val toolbar_DOT_TUNING =
      new GButton.toolbar (GtkButton.Toolbar.cast
        (Glade.get_widget_msg ~name:"toolbar_DOT_TUNING" ~info:"GtkToolbar" xmldata))
    method toolbar_DOT_TUNING = toolbar_DOT_TUNING
    val toolitem65 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem65" ~info:"GtkToolItem" xmldata))
    method toolitem65 = toolitem65
    val label_DOT_TUNING_NODES =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_DOT_TUNING_NODES" ~info:"GtkLabel" xmldata))
    method label_DOT_TUNING_NODES = label_DOT_TUNING_NODES
    val toolitem254 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem254" ~info:"GtkToolItem" xmldata))
    method toolitem254 = toolitem254
    val vscale_DOT_TUNING_ICONSIZE =
      new GRange.scale (GtkRange.Scale.cast
        (Glade.get_widget_msg ~name:"vscale_DOT_TUNING_ICONSIZE" ~info:"GtkVScale" xmldata))
    method vscale_DOT_TUNING_ICONSIZE = vscale_DOT_TUNING_ICONSIZE
    val toolitem67 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem67" ~info:"GtkToolItem" xmldata))
    method toolitem67 = toolitem67
    val button_DOT_TUNING_SHUFFLE =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"button_DOT_TUNING_SHUFFLE" ~info:"GtkButton" xmldata))
    method button_DOT_TUNING_SHUFFLE = button_DOT_TUNING_SHUFFLE
    val image450 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image450" ~info:"GtkImage" xmldata))
    method image450 = image450
    val toolitem69 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem69" ~info:"GtkToolItem" xmldata))
    method toolitem69 = toolitem69
    val button_DOT_TUNING_UNSHUFFLE =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"button_DOT_TUNING_UNSHUFFLE" ~info:"GtkButton" xmldata))
    method button_DOT_TUNING_UNSHUFFLE = button_DOT_TUNING_UNSHUFFLE
    val image580 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image580" ~info:"GtkImage" xmldata))
    method image580 = image580
    val toolitem68 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem68" ~info:"GtkToolItem" xmldata))
    method toolitem68 = toolitem68
    val hseparator83 =
      new GObj.widget_full (GtkMisc.Separator.cast
        (Glade.get_widget_msg ~name:"hseparator83" ~info:"GtkHSeparator" xmldata))
    method hseparator83 = hseparator83
    val toolitem651 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem651" ~info:"GtkToolItem" xmldata))
    method toolitem651 = toolitem651
    val label_DOT_TUNING_EDGES =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_DOT_TUNING_EDGES" ~info:"GtkLabel" xmldata))
    method label_DOT_TUNING_EDGES = label_DOT_TUNING_EDGES
    val toolitem244 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem244" ~info:"GtkToolItem" xmldata))
    method toolitem244 = toolitem244
    val button_DOT_TUNING_RANKDIR_TB =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"button_DOT_TUNING_RANKDIR_TB" ~info:"GtkButton" xmldata))
    method button_DOT_TUNING_RANKDIR_TB = button_DOT_TUNING_RANKDIR_TB
    val image670 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image670" ~info:"GtkImage" xmldata))
    method image670 = image670
    val toolitem246 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem246" ~info:"GtkToolItem" xmldata))
    method toolitem246 = toolitem246
    val button_DOT_TUNING_RANKDIR_LR =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"button_DOT_TUNING_RANKDIR_LR" ~info:"GtkButton" xmldata))
    method button_DOT_TUNING_RANKDIR_LR = button_DOT_TUNING_RANKDIR_LR
    val image780 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image780" ~info:"GtkImage" xmldata))
    method image780 = image780
    val toolitem247 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem247" ~info:"GtkToolItem" xmldata))
    method toolitem247 = toolitem247
    val vscale_DOT_TUNING_NODESEP =
      new GRange.scale (GtkRange.Scale.cast
        (Glade.get_widget_msg ~name:"vscale_DOT_TUNING_NODESEP" ~info:"GtkVScale" xmldata))
    method vscale_DOT_TUNING_NODESEP = vscale_DOT_TUNING_NODESEP
    val toolitem248 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem248" ~info:"GtkToolItem" xmldata))
    method toolitem248 = toolitem248
    val menubar_DOT_TUNING_INVERT =
      new GMenu.menu_shell (GtkMenu.MenuBar.cast
        (Glade.get_widget_msg ~name:"menubar_DOT_TUNING_INVERT" ~info:"GtkMenuBar" xmldata))
    method menubar_DOT_TUNING_INVERT = menubar_DOT_TUNING_INVERT
    val imagemenuitem_DOT_TUNING_INVERT =
      new GMenu.image_menu_item (GtkMenu.ImageMenuItem.cast
        (Glade.get_widget_msg ~name:"imagemenuitem_DOT_TUNING_INVERT" ~info:"GtkImageMenuItem" xmldata))
    method imagemenuitem_DOT_TUNING_INVERT = imagemenuitem_DOT_TUNING_INVERT
    val imagemenuitem_DOT_TUNING_INVERT_menu =
      new GMenu.menu (GtkMenu.Menu.cast
        (Glade.get_widget_msg ~name:"imagemenuitem_DOT_TUNING_INVERT_menu" ~info:"GtkMenu" xmldata))
    method imagemenuitem_DOT_TUNING_INVERT_menu = imagemenuitem_DOT_TUNING_INVERT_menu
    val imagemenuitem_DOT_TUNING_INVERT_DIRECT =
      new GMenu.image_menu_item (GtkMenu.ImageMenuItem.cast
        (Glade.get_widget_msg ~name:"imagemenuitem_DOT_TUNING_INVERT_DIRECT" ~info:"GtkImageMenuItem" xmldata))
    method imagemenuitem_DOT_TUNING_INVERT_DIRECT = imagemenuitem_DOT_TUNING_INVERT_DIRECT
    val imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu =
      new GMenu.menu (GtkMenu.Menu.cast
        (Glade.get_widget_msg ~name:"imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu" ~info:"GtkMenu" xmldata))
    method imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu = imagemenuitem_DOT_TUNING_INVERT_DIRECT_menu
    val item127 =
      new GMenu.check_menu_item (GtkMenu.CheckMenuItem.cast
        (Glade.get_widget_msg ~name:"item127" ~info:"GtkCheckMenuItem" xmldata))
    method item127 = item127
    val menu_item_image53 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"menu-item-image53" ~info:"GtkImage" xmldata))
    method menu_item_image53 = menu_item_image53
    val imagemenuitem_DOT_TUNING_INVERT_CROSSOVER =
      new GMenu.image_menu_item (GtkMenu.ImageMenuItem.cast
        (Glade.get_widget_msg ~name:"imagemenuitem_DOT_TUNING_INVERT_CROSSOVER" ~info:"GtkImageMenuItem" xmldata))
    method imagemenuitem_DOT_TUNING_INVERT_CROSSOVER = imagemenuitem_DOT_TUNING_INVERT_CROSSOVER
    val imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu =
      new GMenu.menu (GtkMenu.Menu.cast
        (Glade.get_widget_msg ~name:"imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu" ~info:"GtkMenu" xmldata))
    method imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu = imagemenuitem_DOT_TUNING_INVERT_CROSSOVER_menu
    val menuitem17 =
      new GMenu.check_menu_item (GtkMenu.CheckMenuItem.cast
        (Glade.get_widget_msg ~name:"menuitem17" ~info:"GtkCheckMenuItem" xmldata))
    method menuitem17 = menuitem17
    val menu_item_image54 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"menu-item-image54" ~info:"GtkImage" xmldata))
    method menu_item_image54 = menu_item_image54
    val menu_item_image56 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"menu-item-image56" ~info:"GtkImage" xmldata))
    method menu_item_image56 = menu_item_image56
    val toolitem251 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem251" ~info:"GtkToolItem" xmldata))
    method toolitem251 = toolitem251
    val button_DOT_TUNING_CURVED_LINES =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"button_DOT_TUNING_CURVED_LINES" ~info:"GtkButton" xmldata))
    method button_DOT_TUNING_CURVED_LINES = button_DOT_TUNING_CURVED_LINES
    val image671 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image671" ~info:"GtkImage" xmldata))
    method image671 = image671
    val toolitem249 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem249" ~info:"GtkToolItem" xmldata))
    method toolitem249 = toolitem249
    val hseparator84 =
      new GObj.widget_full (GtkMisc.Separator.cast
        (Glade.get_widget_msg ~name:"hseparator84" ~info:"GtkHSeparator" xmldata))
    method hseparator84 = hseparator84
    val toolitem250 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem250" ~info:"GtkToolItem" xmldata))
    method toolitem250 = toolitem250
    val label_DOT_TUNING_LABELS =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_DOT_TUNING_LABELS" ~info:"GtkLabel" xmldata))
    method label_DOT_TUNING_LABELS = label_DOT_TUNING_LABELS
    val toolitem258 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem258" ~info:"GtkToolItem" xmldata))
    method toolitem258 = toolitem258
    val vscale_DOT_TUNING_LABELDISTANCE =
      new GRange.scale (GtkRange.Scale.cast
        (Glade.get_widget_msg ~name:"vscale_DOT_TUNING_LABELDISTANCE" ~info:"GtkVScale" xmldata))
    method vscale_DOT_TUNING_LABELDISTANCE = vscale_DOT_TUNING_LABELDISTANCE
    val toolitem261 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem261" ~info:"GtkToolItem" xmldata))
    method toolitem261 = toolitem261
    val hseparator85 =
      new GObj.widget_full (GtkMisc.Separator.cast
        (Glade.get_widget_msg ~name:"hseparator85" ~info:"GtkHSeparator" xmldata))
    method hseparator85 = hseparator85
    val toolitem255 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem255" ~info:"GtkToolItem" xmldata))
    method toolitem255 = toolitem255
    val label_DOT_TUNING_AREA =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_DOT_TUNING_AREA" ~info:"GtkLabel" xmldata))
    method label_DOT_TUNING_AREA = label_DOT_TUNING_AREA
    val toolitem269 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem269" ~info:"GtkToolItem" xmldata))
    method toolitem269 = toolitem269
    val vscale_DOT_TUNING_EXTRASIZE =
      new GRange.scale (GtkRange.Scale.cast
        (Glade.get_widget_msg ~name:"vscale_DOT_TUNING_EXTRASIZE" ~info:"GtkVScale" xmldata))
    method vscale_DOT_TUNING_EXTRASIZE = vscale_DOT_TUNING_EXTRASIZE
    val toolitem268 =
      new GButton.tool_item (GtkButton.ToolItem.cast
        (Glade.get_widget_msg ~name:"toolitem268" ~info:"GtkToolItem" xmldata))
    method toolitem268 = toolitem268
    val hseparator86 =
      new GObj.widget_full (GtkMisc.Separator.cast
        (Glade.get_widget_msg ~name:"hseparator86" ~info:"GtkHSeparator" xmldata))
    method hseparator86 = hseparator86
    val label_IMAGE =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_IMAGE" ~info:"GtkLabel" xmldata))
    method label_IMAGE = label_IMAGE
    val ifconfig_viewport =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"ifconfig_viewport" ~info:"GtkHBox" xmldata))
    method ifconfig_viewport = ifconfig_viewport
    val label_INTERFACES =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_INTERFACES" ~info:"GtkLabel" xmldata))
    method label_INTERFACES = label_INTERFACES
    val defects_viewport =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"defects_viewport" ~info:"GtkHBox" xmldata))
    method defects_viewport = defects_viewport
    val label_DEFECT =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_DEFECT" ~info:"GtkLabel" xmldata))
    method label_DEFECT = label_DEFECT
    val filesystem_history_viewport =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"filesystem_history_viewport" ~info:"GtkHBox" xmldata))
    method filesystem_history_viewport = filesystem_history_viewport
    val label_DISKS =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_DISKS" ~info:"GtkLabel" xmldata))
    method label_DISKS = label_DISKS
    val label_COMPONENTS =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_COMPONENTS" ~info:"GtkLabel" xmldata))
    method label_COMPONENTS = label_COMPONENTS
    val vbox555775 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox555775" ~info:"GtkVBox" xmldata))
    method vbox555775 = vbox555775
    val label_TAB_DOCUMENTS =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_TAB_DOCUMENTS" ~info:"GtkLabel" xmldata))
    method label_TAB_DOCUMENTS = label_TAB_DOCUMENTS
    val documents_viewport =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"documents_viewport" ~info:"GtkHBox" xmldata))
    method documents_viewport = documents_viewport
    val label_ENONCE =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_ENONCE" ~info:"GtkLabel" xmldata))
    method label_ENONCE = label_ENONCE
    val hbox_BASE =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox_BASE" ~info:"GtkHBox" xmldata))
    method hbox_BASE = hbox_BASE
    val statusbar =
      new GMisc.statusbar (GtkMisc.Statusbar.cast
        (Glade.get_widget_msg ~name:"statusbar" ~info:"GtkStatusbar" xmldata))
    method statusbar = statusbar
    method reparent parent =
      vbox1#misc#reparent parent;
      toplevel#destroy ()
    method check_widgets () = ()
  end
class dialog_A_PROPOS ?(file="gui.glade.patched") ?domain ?autoconnect(*=true*) () =
  let xmldata = Glade.create ~file  ~root:"dialog_A_PROPOS" ?domain () in
  object (self)
    inherit Glade.xml ?autoconnect xmldata
    val toplevel =
      new GWindow.dialog_any (GtkWindow.Dialog.cast
        (Glade.get_widget_msg ~name:"dialog_A_PROPOS" ~info:"GtkDialog" xmldata))
    method toplevel = toplevel
    val dialog_A_PROPOS =
      new GWindow.dialog_any (GtkWindow.Dialog.cast
        (Glade.get_widget_msg ~name:"dialog_A_PROPOS" ~info:"GtkDialog" xmldata))
    method dialog_A_PROPOS = dialog_A_PROPOS
    val dialog_vbox2 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"dialog-vbox2" ~info:"GtkVBox" xmldata))
    method dialog_vbox2 = dialog_vbox2
    val vbox10 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox10" ~info:"GtkVBox" xmldata))
    method vbox10 = vbox10
    val label_dialog_A_PROPOS_title =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_title" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_title = label_dialog_A_PROPOS_title
    val hbox50 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox50" ~info:"GtkHBox" xmldata))
    method hbox50 = hbox50
    val scrolledwindow11 =
      new GBin.scrolled_window (GtkBin.ScrolledWindow.cast
        (Glade.get_widget_msg ~name:"scrolledwindow11" ~info:"GtkScrolledWindow" xmldata))
    method scrolledwindow11 = scrolledwindow11
    val viewport10 =
      new GBin.viewport (GtkBin.Viewport.cast
        (Glade.get_widget_msg ~name:"viewport10" ~info:"GtkViewport" xmldata))
    method viewport10 = viewport10
    val image366 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image366" ~info:"GtkImage" xmldata))
    method image366 = image366
    val notebook_dialog_A_PROPOS =
      new GPack.notebook (GtkPack.Notebook.cast
        (Glade.get_widget_msg ~name:"notebook_dialog_A_PROPOS" ~info:"GtkNotebook" xmldata))
    method notebook_dialog_A_PROPOS = notebook_dialog_A_PROPOS
    val label_dialog_A_PROPOS_a_propos_content =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_a_propos_content" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_a_propos_content = label_dialog_A_PROPOS_a_propos_content
    val label_dialog_A_PROPOS_a_propos =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_a_propos" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_a_propos = label_dialog_A_PROPOS_a_propos
    val label_dialog_A_PROPOS_authors_content =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_authors_content" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_authors_content = label_dialog_A_PROPOS_authors_content
    val label_dialog_A_PROPOS_authors =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_authors" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_authors = label_dialog_A_PROPOS_authors
    val label_dialog_A_PROPOS_license_content =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_license_content" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_license_content = label_dialog_A_PROPOS_license_content
    val label_dialog_A_PROPOS_license =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_license" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_license = label_dialog_A_PROPOS_license
    val vbox8 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox8" ~info:"GtkVBox" xmldata))
    method vbox8 = vbox8
    val label_dialog_A_PROPOS_thanks_content =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_thanks_content" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_thanks_content = label_dialog_A_PROPOS_thanks_content
    val hbox2 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox2" ~info:"GtkHBox" xmldata))
    method hbox2 = hbox2
    val label_dialog_A_PROPOS_thanks_sponsors =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_thanks_sponsors" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_thanks_sponsors = label_dialog_A_PROPOS_thanks_sponsors
    val image23 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image23" ~info:"GtkImage" xmldata))
    method image23 = image23
    val label_dialog_A_PROPOS_thanks =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"label_dialog_A_PROPOS_thanks" ~info:"GtkLabel" xmldata))
    method label_dialog_A_PROPOS_thanks = label_dialog_A_PROPOS_thanks
    val dialog_action_area2 =
      new GPack.button_box (GtkPack.BBox.cast
        (Glade.get_widget_msg ~name:"dialog-action_area2" ~info:"GtkHButtonBox" xmldata))
    method dialog_action_area2 = dialog_action_area2
    val closebutton_A_PROPOS =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"closebutton_A_PROPOS" ~info:"GtkButton" xmldata))
    method closebutton_A_PROPOS = closebutton_A_PROPOS
    method reparent parent =
      dialog_vbox2#misc#reparent parent;
      toplevel#destroy ()
    method check_widgets () = ()
  end
class dialog_MESSAGE ?(file="gui.glade.patched") ?domain ?autoconnect(*=true*) () =
  let xmldata = Glade.create ~file  ~root:"dialog_MESSAGE" ?domain () in
  object (self)
    inherit Glade.xml ?autoconnect xmldata
    val toplevel =
      new GWindow.dialog_any (GtkWindow.Dialog.cast
        (Glade.get_widget_msg ~name:"dialog_MESSAGE" ~info:"GtkDialog" xmldata))
    method toplevel = toplevel
    val dialog_MESSAGE =
      new GWindow.dialog_any (GtkWindow.Dialog.cast
        (Glade.get_widget_msg ~name:"dialog_MESSAGE" ~info:"GtkDialog" xmldata))
    method dialog_MESSAGE = dialog_MESSAGE
    val dialog_vbox3 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"dialog-vbox3" ~info:"GtkVBox" xmldata))
    method dialog_vbox3 = dialog_vbox3
    val vbox11 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox11" ~info:"GtkVBox" xmldata))
    method vbox11 = vbox11
    val hbox51 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox51" ~info:"GtkHBox" xmldata))
    method hbox51 = hbox51
    val image =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image" ~info:"GtkImage" xmldata))
    method image = image
    val title =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"title" ~info:"GtkLabel" xmldata))
    method title = title
    val content =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"content" ~info:"GtkLabel" xmldata))
    method content = content
    val dialog_action_area3 =
      new GPack.button_box (GtkPack.BBox.cast
        (Glade.get_widget_msg ~name:"dialog-action_area3" ~info:"GtkHButtonBox" xmldata))
    method dialog_action_area3 = dialog_action_area3
    val closebutton_MESSAGE =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"closebutton_MESSAGE" ~info:"GtkButton" xmldata))
    method closebutton_MESSAGE = closebutton_MESSAGE
    method reparent parent =
      dialog_vbox3#misc#reparent parent;
      toplevel#destroy ()
    method check_widgets () = ()
  end
class dialog_QUESTION ?(file="gui.glade.patched") ?domain ?autoconnect(*=true*) () =
  let xmldata = Glade.create ~file  ~root:"dialog_QUESTION" ?domain () in
  object (self)
    inherit Glade.xml ?autoconnect xmldata
    val toplevel =
      new GWindow.dialog_any (GtkWindow.Dialog.cast
        (Glade.get_widget_msg ~name:"dialog_QUESTION" ~info:"GtkDialog" xmldata))
    method toplevel = toplevel
    val dialog_QUESTION =
      new GWindow.dialog_any (GtkWindow.Dialog.cast
        (Glade.get_widget_msg ~name:"dialog_QUESTION" ~info:"GtkDialog" xmldata))
    method dialog_QUESTION = dialog_QUESTION
    val vbox12 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox12" ~info:"GtkVBox" xmldata))
    method vbox12 = vbox12
    val vbox13 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"vbox13" ~info:"GtkVBox" xmldata))
    method vbox13 = vbox13
    val hbox52 =
      new GPack.box (GtkPack.Box.cast
        (Glade.get_widget_msg ~name:"hbox52" ~info:"GtkHBox" xmldata))
    method hbox52 = hbox52
    val image399 =
      new GMisc.image (GtkMisc.Image.cast
        (Glade.get_widget_msg ~name:"image399" ~info:"GtkImage" xmldata))
    method image399 = image399
    val title_QUESTION =
      new GMisc.label (GtkMisc.Label.cast
        (Glade.get_widget_msg ~name:"title_QUESTION" ~info:"GtkLabel" xmldata))
    method title_QUESTION = title_QUESTION
    val hbuttonbox3 =
      new GPack.button_box (GtkPack.BBox.cast
        (Glade.get_widget_msg ~name:"hbuttonbox3" ~info:"GtkHButtonBox" xmldata))
    method hbuttonbox3 = hbuttonbox3
    val nobutton =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"nobutton" ~info:"GtkButton" xmldata))
    method nobutton = nobutton
    val yesbutton =
      new GButton.button (GtkButton.Button.cast
        (Glade.get_widget_msg ~name:"yesbutton" ~info:"GtkButton" xmldata))
    method yesbutton = yesbutton
    method reparent parent =
      vbox12#misc#reparent parent;
      toplevel#destroy ()
    method check_widgets () = ()
  end
