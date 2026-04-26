package com.github.caciocavallosilano.cacio.peer.managed;

import com.github.caciocavallosilano.cacio.peer.CacioComponent;
import com.github.caciocavallosilano.cacio.peer.CacioEventPump;
import com.github.caciocavallosilano.cacio.peer.CacioEventSource;
import com.github.caciocavallosilano.cacio.peer.PlatformToplevelWindow;
import com.github.caciocavallosilano.cacio.peer.PlatformWindow;
import com.github.caciocavallosilano.cacio.peer.PlatformWindowFactory;
import java.awt.Dimension;
import java.awt.GraphicsConfiguration;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;

public class FullScreenWindowFactory implements PlatformWindowFactory {
    private static final Dimension screenSize;

    private final PlatformScreenSelector selector;
    private final Map<PlatformScreen, ScreenManagedWindowContainer> screenMap;
    private CacioEventSource eventSource;

    public FullScreenWindowFactory(PlatformScreen screen, CacioEventSource eventSource) {
        this(new DefaultScreenSelector(screen), eventSource);
    }

    public FullScreenWindowFactory(PlatformScreenSelector selector, CacioEventSource eventSource) {
        this.selector = selector;
        this.eventSource = eventSource;
        this.screenMap = Collections.synchronizedMap(new HashMap<>());
    }

    @Override
    public final PlatformWindow createPlatformWindow(CacioComponent cacioComponent, PlatformWindow parent) {
        if (parent == null) {
            throw new IllegalArgumentException("parent cannot be null");
        }
        return new ManagedWindow((ManagedWindow) parent, cacioComponent);
    }

    @Override
    public final PlatformToplevelWindow createPlatformToplevelWindow(CacioComponent cacioComponent) {
        PlatformScreen screen = selector.getPlatformScreen(cacioComponent);
        ScreenManagedWindowContainer container = screenMap.get(screen);
        if (container == null) {
            container = new ScreenManagedWindowContainer(screen);
            screenMap.put(screen, container);
        }
        return new ManagedWindow(container, cacioComponent);
    }

    @Override
    public PlatformWindow createPlatformToplevelWindow(CacioComponent cacioComponent, PlatformWindow parent) {
        return createPlatformToplevelWindow(cacioComponent);
    }

    @Override
    public CacioEventPump<?> createEventPump() {
        return new FullScreenEventPump(new FullScreenEventSource());
    }

    public static Dimension getScreenDimension() {
        return screenSize;
    }

    public ScreenManagedWindowContainer getScreenManagedWindowContainer(PlatformScreen screen) {
        return screenMap.get(screen);
    }

    static {
        String size = System.getProperty("cacio.managed.screensize", "1024x768");
        int separator = size.indexOf('x');
        if (separator <= 0 || separator >= size.length() - 1) {
            size = "1024x768";
            separator = size.indexOf('x');
        }
        int width = Integer.parseInt(size.substring(0, separator));
        int height = Integer.parseInt(size.substring(separator + 1));
        screenSize = new Dimension(width, height);
    }

    static final class DefaultScreenSelector implements PlatformScreenSelector {
        private PlatformScreen screen;

        DefaultScreenSelector(PlatformScreen screen) {
            this.screen = screen;
        }

        @Override
        public PlatformScreen getPlatformScreen(GraphicsConfiguration graphicsConfiguration) {
            return screen;
        }

        @Override
        public PlatformScreen getPlatformScreen(CacioComponent cacioComponent) {
            return getPlatformScreen(cacioComponent.getAWTComponent().getGraphicsConfiguration());
        }
    }

    final class FullScreenEventSource implements CacioEventSource {
        @Override
        public EventData getNextEvent() throws InterruptedException {
            EventData event = eventSource.getNextEvent();
            PlatformScreen screen = (PlatformScreen) event.getSource();
            event.setSource(screenMap.get(screen));
            return event;
        }
    }
}
